package wallet

import (
	"context"
	"crypto/rand"
	"database/sql"
	"encoding/json"
	"errors"
	"math/big"
	"strconv"
	"strings"
	"time"

	"bim/server/internal/platform/database"
)

type SQLRepository struct{ db *database.DB }

func NewSQLRepository(db *database.DB) *SQLRepository { return &SQLRepository{db: db} }

func (r *SQLRepository) Balance(ctx context.Context, appID, userID uint64) (Balance, error) {
	if err := r.ensureAccount(ctx, appID, userID); err != nil {
		return Balance{}, err
	}
	var balance Balance
	err := r.db.QueryRowContext(ctx, `SELECT available_amount,frozen_amount,currency,status,lock_reason FROM wallet_accounts WHERE app_id=? AND user_id=? AND currency='CNY'`, appID, userID).Scan(&balance.Available, &balance.Frozen, &balance.Currency, &balance.Status, &balance.LockReason)
	return balance, err
}

func (r *SQLRepository) HasVerifiedSecurityMethod(ctx context.Context, appID, userID uint64) (bool, error) {
	var count int
	err := r.db.QueryRowContext(ctx, `SELECT COUNT(*) FROM user_credentials c JOIN users u ON u.id=c.user_id WHERE u.app_id=? AND u.id=? AND c.credential_type IN ('phone','email') AND c.verified_at IS NOT NULL`, appID, userID).Scan(&count)
	return count > 0, err
}

func (r *SQLRepository) SecurityIdentifier(ctx context.Context, appID, userID uint64, method string) (string, error) {
	var identifier string
	err := r.db.QueryRowContext(ctx, `SELECT c.identifier FROM user_credentials c JOIN users u ON u.id=c.user_id WHERE u.app_id=? AND u.id=? AND c.credential_type=? AND c.verified_at IS NOT NULL LIMIT 1`, appID, userID, method).Scan(&identifier)
	return identifier, err
}
func (r *SQLRepository) ensureAccount(ctx context.Context, appID, userID uint64) error {
	_, err := r.db.ExecContext(ctx, `INSERT INTO wallet_accounts(app_id,user_id,currency,created_at,updated_at) SELECT ?,?,'CNY',NOW(6),NOW(6) FROM DUAL WHERE EXISTS(SELECT 1 FROM users WHERE app_id=? AND id=? AND status=1) ON DUPLICATE KEY UPDATE updated_at=updated_at`, appID, userID, appID, userID)
	return err
}
func (r *SQLRepository) SetPaymentPassword(ctx context.Context, appID, userID uint64, hash string) error {
	_, err := r.db.ExecContext(ctx, `INSERT INTO wallet_credentials(app_id,user_id,password_hash,failed_attempts,locked_until,created_at,updated_at) VALUES(?,?,?,0,NULL,NOW(6),NOW(6)) ON DUPLICATE KEY UPDATE password_hash=VALUES(password_hash),failed_attempts=0,locked_until=NULL,updated_at=NOW(6)`, appID, userID, hash)
	return err
}
func (r *SQLRepository) PaymentCredential(ctx context.Context, appID, userID uint64) (string, uint8, *time.Time, error) {
	var hash string
	var attempts uint8
	var locked sql.NullTime
	err := r.db.QueryRowContext(ctx, `SELECT password_hash,failed_attempts,locked_until FROM wallet_credentials WHERE app_id=? AND user_id=?`, appID, userID).Scan(&hash, &attempts, &locked)
	if locked.Valid {
		return hash, attempts, &locked.Time, err
	}
	return hash, attempts, nil, err
}
func (r *SQLRepository) RecordPasswordFailure(ctx context.Context, appID, userID uint64, attempts uint8, lockedUntil *time.Time) error {
	_, err := r.db.ExecContext(ctx, `UPDATE wallet_credentials SET failed_attempts=?,locked_until=?,updated_at=NOW(6) WHERE app_id=? AND user_id=?`, attempts, lockedUntil, appID, userID)
	return err
}
func (r *SQLRepository) ResetPasswordFailures(ctx context.Context, appID, userID uint64) error {
	_, err := r.db.ExecContext(ctx, `UPDATE wallet_credentials SET failed_attempts=0,locked_until=NULL,updated_at=NOW(6) WHERE app_id=? AND user_id=?`, appID, userID)
	return err
}

type lockedAccount struct {
	id                uint64
	available, frozen int64
	status            string
}

func (r *SQLRepository) lockAccount(ctx context.Context, tx *sql.Tx, appID, userID uint64) (lockedAccount, error) {
	var account lockedAccount
	err := tx.QueryRowContext(ctx, `SELECT id,available_amount,frozen_amount,status FROM wallet_accounts WHERE app_id=? AND user_id=? AND currency='CNY' FOR UPDATE`, appID, userID).Scan(&account.id, &account.available, &account.frozen, &account.status)
	if errors.Is(err, sql.ErrNoRows) {
		_, err = tx.ExecContext(ctx, `INSERT INTO wallet_accounts(app_id,user_id,currency,created_at,updated_at) SELECT ?,?,'CNY',NOW(6),NOW(6) FROM DUAL WHERE EXISTS(SELECT 1 FROM users WHERE app_id=? AND id=? AND status=1)`, appID, userID, appID, userID)
		if err != nil {
			return account, err
		}
		err = tx.QueryRowContext(ctx, `SELECT id,available_amount,frozen_amount,status FROM wallet_accounts WHERE app_id=? AND user_id=? AND currency='CNY' FOR UPDATE`, appID, userID).Scan(&account.id, &account.available, &account.frozen, &account.status)
	}
	return account, err
}

func (r *SQLRepository) CreateTransfer(ctx context.Context, appID, senderID, recipientID uint64, amount int64, orderNo string, expiresAt time.Time) (Transfer, error) {
	var transfer Transfer
	err := r.db.WithinTx(ctx, &sql.TxOptions{Isolation: sql.LevelReadCommitted}, func(tx *sql.Tx) error {
		sender, err := r.lockAccount(ctx, tx, appID, senderID)
		if err != nil {
			return err
		}
		if sender.status != "active" {
			return ErrWalletLocked
		}
		if sender.available < amount {
			return ErrInsufficientBalance
		}
		var recipientExists int
		if err := tx.QueryRowContext(ctx, `SELECT COUNT(*) FROM users WHERE app_id=? AND id=? AND status=1`, appID, recipientID).Scan(&recipientExists); err != nil {
			return err
		}
		if recipientExists != 1 {
			return ErrOrderNotFound
		}
		now := time.Now().UTC()
		result, err := tx.ExecContext(ctx, `INSERT INTO wallet_transfers(app_id,order_no,sender_id,recipient_id,amount,status,expires_at,created_at,updated_at) VALUES(?,?,?,?,?,'pending',?,?,?)`, appID, orderNo, senderID, recipientID, amount, expiresAt, now, now)
		if err != nil {
			return err
		}
		transferID, err := result.LastInsertId()
		if err != nil {
			return err
		}
		transactionID, err := r.createTransaction(ctx, tx, appID, "transfer_freeze", "transfer", orderNo, amount, now)
		if err != nil {
			return err
		}
		newAvailable := sender.available - amount
		newFrozen := sender.frozen + amount
		if _, err := tx.ExecContext(ctx, `UPDATE wallet_accounts SET available_amount=?,frozen_amount=?,version=version+1,updated_at=? WHERE id=?`, newAvailable, newFrozen, now, sender.id); err != nil {
			return err
		}
		if err := r.entry(ctx, tx, appID, transactionID, sender.id, "available_debit", amount, newAvailable, now); err != nil {
			return err
		}
		if err := r.entry(ctx, tx, appID, transactionID, sender.id, "frozen_credit", amount, newFrozen, now); err != nil {
			return err
		}
		transfer = Transfer{ID: uint64(transferID), OrderNo: orderNo, SenderID: senderID, RecipientID: recipientID, Amount: amount, Status: "pending", ExpiresAt: expiresAt, CreatedAt: now}
		channelID := "app" + strconv.FormatUint(appID, 10) + "user" + strconv.FormatUint(recipientID, 10)
		if _, err := enqueueChatMessage(ctx, tx, appID, senderID, channelID, 1, 5101, map[string]any{"order_no": orderNo, "status": "pending", "amount": amount, "summary": "[转账]请收款", "expires_at": expiresAt}, now); err != nil {
			return err
		}
		if err := enqueuePaymentNotice(ctx, tx, appID, senderID, "transfer_created", map[string]any{"order_no": orderNo, "status": "pending", "amount": amount, "title": "转账已发起"}, now); err != nil {
			return err
		}
		return nil
	})
	return transfer, err
}

func (r *SQLRepository) AcceptTransfer(ctx context.Context, appID, recipientID uint64, orderNo string) (Transfer, error) {
	var transfer Transfer
	err := r.db.WithinTx(ctx, &sql.TxOptions{Isolation: sql.LevelReadCommitted}, func(tx *sql.Tx) error {
		err := tx.QueryRowContext(ctx, `SELECT id,order_no,sender_id,recipient_id,amount,status,expires_at,created_at FROM wallet_transfers WHERE app_id=? AND order_no=? FOR UPDATE`, appID, orderNo).Scan(&transfer.ID, &transfer.OrderNo, &transfer.SenderID, &transfer.RecipientID, &transfer.Amount, &transfer.Status, &transfer.ExpiresAt, &transfer.CreatedAt)
		if errors.Is(err, sql.ErrNoRows) {
			return ErrOrderNotFound
		}
		if err != nil {
			return err
		}
		if transfer.RecipientID != recipientID {
			return ErrOrderNotFound
		}
		if transfer.Status != "pending" {
			return ErrOrderState
		}
		if !transfer.ExpiresAt.After(time.Now().UTC()) {
			return ErrOrderState
		}
		sender, recipient, err := r.lockAccountPair(ctx, tx, appID, transfer.SenderID, transfer.RecipientID)
		if err != nil {
			return err
		}
		if recipient.status != "active" {
			return ErrWalletLocked
		}
		if sender.frozen < transfer.Amount {
			return ErrOrderState
		}
		now := time.Now().UTC()
		transactionID, err := r.createTransaction(ctx, tx, appID, "transfer_settle", "transfer", orderNo, transfer.Amount, now)
		if err != nil {
			return err
		}
		senderFrozen := sender.frozen - transfer.Amount
		recipientAvailable := recipient.available + transfer.Amount
		if _, err := tx.ExecContext(ctx, `UPDATE wallet_accounts SET frozen_amount=?,version=version+1,updated_at=? WHERE id=?`, senderFrozen, now, sender.id); err != nil {
			return err
		}
		if _, err := tx.ExecContext(ctx, `UPDATE wallet_accounts SET available_amount=?,version=version+1,updated_at=? WHERE id=?`, recipientAvailable, now, recipient.id); err != nil {
			return err
		}
		if err := r.entry(ctx, tx, appID, transactionID, sender.id, "frozen_debit", transfer.Amount, senderFrozen, now); err != nil {
			return err
		}
		if err := r.entry(ctx, tx, appID, transactionID, recipient.id, "available_credit", transfer.Amount, recipientAvailable, now); err != nil {
			return err
		}
		if _, err := tx.ExecContext(ctx, `UPDATE wallet_transfers SET status='accepted',accepted_at=?,updated_at=? WHERE id=?`, now, now, transfer.ID); err != nil {
			return err
		}
		transfer.Status = "accepted"
		channelID := "app" + strconv.FormatUint(appID, 10) + "user" + strconv.FormatUint(transfer.SenderID, 10)
		if _, err := enqueueChatMessage(ctx, tx, appID, recipientID, channelID, 1, 5104, map[string]any{"order_no": orderNo, "status": "accepted", "summary": "已收款"}, now); err != nil {
			return err
		}
		if err := enqueuePaymentNotice(ctx, tx, appID, transfer.SenderID, "transfer_accepted", map[string]any{"order_no": orderNo, "status": "accepted", "amount": transfer.Amount, "title": "对方已收款"}, now); err != nil {
			return err
		}
		if err := enqueuePaymentNotice(ctx, tx, appID, recipientID, "transfer_received", map[string]any{"order_no": orderNo, "status": "accepted", "amount": transfer.Amount, "title": "转账已到账"}, now); err != nil {
			return err
		}
		return nil
	})
	return transfer, err
}

func (r *SQLRepository) lockAccountPair(ctx context.Context, tx *sql.Tx, appID, firstUserID, secondUserID uint64) (lockedAccount, lockedAccount, error) {
	if firstUserID == secondUserID {
		account, err := r.lockAccount(ctx, tx, appID, firstUserID)
		return account, account, err
	}
	lowID, highID := firstUserID, secondUserID
	if lowID > highID {
		lowID, highID = highID, lowID
	}
	low, err := r.lockAccount(ctx, tx, appID, lowID)
	if err != nil {
		return lockedAccount{}, lockedAccount{}, err
	}
	high, err := r.lockAccount(ctx, tx, appID, highID)
	if err != nil {
		return lockedAccount{}, lockedAccount{}, err
	}
	if firstUserID == lowID {
		return low, high, nil
	}
	return high, low, nil
}

func (r *SQLRepository) RefundExpiredTransfers(ctx context.Context, limit int) (int, error) {
	rows, err := r.db.QueryContext(ctx, `SELECT order_no FROM wallet_transfers WHERE status='pending' AND expires_at<=NOW(6) ORDER BY id LIMIT ?`, limit)
	if err != nil {
		return 0, err
	}
	orders := []string{}
	for rows.Next() {
		var order string
		if err := rows.Scan(&order); err != nil {
			rows.Close()
			return 0, err
		}
		orders = append(orders, order)
	}
	rows.Close()
	count := 0
	for _, order := range orders {
		ok, err := r.refundTransfer(ctx, order)
		if err != nil {
			return count, err
		}
		if ok {
			count++
		}
	}
	return count, nil
}
func (r *SQLRepository) refundTransfer(ctx context.Context, orderNo string) (bool, error) {
	refunded := false
	err := r.db.WithinTx(ctx, nil, func(tx *sql.Tx) error {
		var id, appID, senderID uint64
		var amount int64
		var status string
		err := tx.QueryRowContext(ctx, `SELECT id,app_id,sender_id,amount,status FROM wallet_transfers WHERE order_no=? AND expires_at<=NOW(6) FOR UPDATE`, orderNo).Scan(&id, &appID, &senderID, &amount, &status)
		if errors.Is(err, sql.ErrNoRows) {
			return nil
		}
		if err != nil {
			return err
		}
		if status != "pending" {
			return nil
		}
		account, err := r.lockAccount(ctx, tx, appID, senderID)
		if err != nil {
			return err
		}
		if account.frozen < amount {
			return ErrOrderState
		}
		now := time.Now().UTC()
		transactionID, err := r.createTransaction(ctx, tx, appID, "transfer_refund", "transfer", orderNo, amount, now)
		if err != nil {
			return err
		}
		available := account.available + amount
		frozen := account.frozen - amount
		if _, err := tx.ExecContext(ctx, `UPDATE wallet_accounts SET available_amount=?,frozen_amount=?,version=version+1,updated_at=? WHERE id=?`, available, frozen, now, account.id); err != nil {
			return err
		}
		if err := r.entry(ctx, tx, appID, transactionID, account.id, "frozen_debit", amount, frozen, now); err != nil {
			return err
		}
		if err := r.entry(ctx, tx, appID, transactionID, account.id, "available_credit", amount, available, now); err != nil {
			return err
		}
		_, err = tx.ExecContext(ctx, `UPDATE wallet_transfers SET status='refunded',refunded_at=?,updated_at=? WHERE id=?`, now, now, id)
		if err == nil {
			err = enqueuePaymentNotice(ctx, tx, appID, senderID, "transfer_refunded", map[string]any{"order_no": orderNo, "status": "refunded", "amount": amount, "title": "转账已退回"}, now)
		}
		refunded = err == nil
		return err
	})
	return refunded, err
}

func (r *SQLRepository) createTransaction(ctx context.Context, tx *sql.Tx, appID uint64, transactionType, referenceType, referenceID string, amount int64, now time.Time) (uint64, error) {
	metadata, _ := json.Marshal(map[string]any{})
	result, err := tx.ExecContext(ctx, `INSERT INTO wallet_transactions(app_id,transaction_no,transaction_type,reference_type,reference_id,status,amount,currency,metadata_json,created_at,updated_at) VALUES(?,?,?,?,?,'completed',?,'CNY',?,?,?)`, appID, referenceID+"-"+transactionType, transactionType, referenceType, referenceID, amount, json.RawMessage(metadata), now, now)
	if err != nil {
		return 0, err
	}
	id, err := result.LastInsertId()
	return uint64(id), err
}
func (r *SQLRepository) entry(ctx context.Context, tx *sql.Tx, appID, transactionID, accountID uint64, entryType string, amount, balanceAfter int64, now time.Time) error {
	_, err := tx.ExecContext(ctx, `INSERT INTO wallet_entries(app_id,transaction_id,account_id,entry_type,amount,balance_after,created_at) VALUES(?,?,?,?,?,?,?)`, appID, transactionID, accountID, entryType, amount, balanceAfter, now)
	return err
}

func (r *SQLRepository) CreateRedPacket(ctx context.Context, appID, senderID uint64, channelID string, channelType uint8, packetType string, designatedUserID *uint64, amount int64, count uint32, greeting, orderNo string, expiresAt time.Time) (RedPacket, error) {
	var packet RedPacket
	err := r.db.WithinTx(ctx, nil, func(tx *sql.Tx) error {
		if err := r.authorizeRedPacketChannel(ctx, tx, appID, senderID, channelID, channelType, designatedUserID); err != nil {
			return err
		}
		sender, err := r.lockAccount(ctx, tx, appID, senderID)
		if err != nil {
			return err
		}
		if sender.status != "active" {
			return ErrWalletLocked
		}
		if sender.available < amount {
			return ErrInsufficientBalance
		}
		now := time.Now().UTC()
		result, err := tx.ExecContext(ctx, `INSERT INTO wallet_red_packets(app_id,order_no,sender_id,channel_id,channel_type,packet_type,designated_user_id,total_amount,total_count,remaining_amount,remaining_count,greeting,status,expires_at,created_at,updated_at) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,'active',?,?,?)`, appID, orderNo, senderID, channelID, channelType, packetType, designatedUserID, amount, count, amount, count, greeting, expiresAt, now, now)
		if err != nil {
			return err
		}
		id, err := result.LastInsertId()
		if err != nil {
			return err
		}
		transactionID, err := r.createTransaction(ctx, tx, appID, "red_packet_freeze", "red_packet", orderNo, amount, now)
		if err != nil {
			return err
		}
		available, frozen := sender.available-amount, sender.frozen+amount
		if _, err := tx.ExecContext(ctx, `UPDATE wallet_accounts SET available_amount=?,frozen_amount=?,version=version+1,updated_at=? WHERE id=?`, available, frozen, now, sender.id); err != nil {
			return err
		}
		if err := r.entry(ctx, tx, appID, transactionID, sender.id, "available_debit", amount, available, now); err != nil {
			return err
		}
		if err := r.entry(ctx, tx, appID, transactionID, sender.id, "frozen_credit", amount, frozen, now); err != nil {
			return err
		}
		packet = RedPacket{ID: uint64(id), OrderNo: orderNo, SenderID: senderID, ChannelID: channelID, ChannelType: channelType, PacketType: packetType, TotalAmount: amount, TotalCount: count, RemainingAmount: amount, RemainingCount: count, Greeting: greeting, Status: "active", ExpiresAt: expiresAt, CreatedAt: now}
		if _, err := enqueueChatMessage(ctx, tx, appID, senderID, channelID, channelType, 5102, map[string]any{"order_no": orderNo, "status": "active", "packet_type": packetType, "greeting": greeting, "summary": "[红包]" + greeting, "expires_at": expiresAt}, now); err != nil {
			return err
		}
		if err := enqueuePaymentNotice(ctx, tx, appID, senderID, "red_packet_created", map[string]any{"order_no": orderNo, "status": "active", "amount": amount, "title": "红包已发出"}, now); err != nil {
			return err
		}
		return nil
	})
	return packet, err
}

func (r *SQLRepository) authorizeRedPacketChannel(ctx context.Context, tx *sql.Tx, appID, senderID uint64, channelID string, channelType uint8, designated *uint64) error {
	if channelType == 1 {
		prefix := "app" + strconv.FormatUint(appID, 10) + "user"
		if !strings.HasPrefix(channelID, prefix) {
			return ErrOrderState
		}
		recipient, err := strconv.ParseUint(strings.TrimPrefix(channelID, prefix), 10, 64)
		if err != nil || recipient == senderID {
			return ErrOrderState
		}
		var friends int
		err = tx.QueryRowContext(ctx, `SELECT COUNT(*) FROM friendships WHERE app_id=? AND user_id=? AND friend_id=? AND status='active'`, appID, senderID, recipient).Scan(&friends)
		if err != nil {
			return err
		}
		if friends != 1 {
			return ErrOrderState
		}
		return nil
	}
	var groupID uint64
	if err := tx.QueryRowContext(ctx, `SELECT g.id FROM chat_groups g JOIN group_members gm ON gm.group_id=g.id WHERE g.app_id=? AND g.channel_id=? AND g.status='active' AND gm.user_id=? AND gm.status='active'`, appID, channelID, senderID).Scan(&groupID); err != nil {
		return ErrOrderState
	}
	if designated != nil {
		var member int
		if err := tx.QueryRowContext(ctx, `SELECT COUNT(*) FROM group_members WHERE group_id=? AND user_id=? AND status='active'`, groupID, *designated).Scan(&member); err != nil {
			return err
		}
		if member != 1 {
			return ErrOrderState
		}
	}
	return nil
}

func (r *SQLRepository) ClaimRedPacket(ctx context.Context, appID, userID uint64, orderNo string) (RedPacketClaim, error) {
	var claim RedPacketClaim
	err := r.db.WithinTx(ctx, nil, func(tx *sql.Tx) error {
		var packet RedPacket
		var designated sql.NullInt64
		err := tx.QueryRowContext(ctx, `SELECT id,order_no,sender_id,channel_id,channel_type,packet_type,designated_user_id,total_amount,total_count,remaining_amount,remaining_count,greeting,status,expires_at,created_at FROM wallet_red_packets WHERE app_id=? AND order_no=? FOR UPDATE`, appID, orderNo).Scan(&packet.ID, &packet.OrderNo, &packet.SenderID, &packet.ChannelID, &packet.ChannelType, &packet.PacketType, &designated, &packet.TotalAmount, &packet.TotalCount, &packet.RemainingAmount, &packet.RemainingCount, &packet.Greeting, &packet.Status, &packet.ExpiresAt, &packet.CreatedAt)
		if errors.Is(err, sql.ErrNoRows) {
			return ErrOrderNotFound
		}
		if err != nil {
			return err
		}
		if packet.Status != "active" || packet.RemainingCount == 0 || !packet.ExpiresAt.After(time.Now().UTC()) {
			return ErrOrderState
		}
		if designated.Valid && uint64(designated.Int64) != userID {
			return ErrOrderNotFound
		}
		if err := r.authorizeRedPacketClaim(ctx, tx, appID, userID, packet); err != nil {
			return err
		}
		var existing int
		if err := tx.QueryRowContext(ctx, `SELECT COUNT(*) FROM wallet_red_packet_claims WHERE red_packet_id=? AND user_id=?`, packet.ID, userID).Scan(&existing); err != nil {
			return err
		}
		if existing > 0 {
			return ErrOrderState
		}
		amount, err := claimAmount(packet.PacketType, packet.RemainingAmount, packet.RemainingCount)
		if err != nil {
			return err
		}
		sender, err := r.lockAccount(ctx, tx, appID, packet.SenderID)
		if err != nil {
			return err
		}
		if sender.frozen < amount {
			return ErrOrderState
		}
		now := time.Now().UTC()
		transactionID, err := r.createTransaction(ctx, tx, appID, "red_packet_claim", "red_packet", orderNo+"-"+strconv.FormatUint(userID, 10), amount, now)
		if err != nil {
			return err
		}
		if packet.SenderID == userID {
			available, frozen := sender.available+amount, sender.frozen-amount
			if _, err := tx.ExecContext(ctx, `UPDATE wallet_accounts SET available_amount=?,frozen_amount=?,version=version+1,updated_at=? WHERE id=?`, available, frozen, now, sender.id); err != nil {
				return err
			}
			if err := r.entry(ctx, tx, appID, transactionID, sender.id, "frozen_debit", amount, frozen, now); err != nil {
				return err
			}
			if err := r.entry(ctx, tx, appID, transactionID, sender.id, "available_credit", amount, available, now); err != nil {
				return err
			}
		} else {
			recipient, err := r.lockAccount(ctx, tx, appID, userID)
			if err != nil {
				return err
			}
			if recipient.status != "active" {
				return ErrWalletLocked
			}
			senderFrozen, recipientAvailable := sender.frozen-amount, recipient.available+amount
			if _, err := tx.ExecContext(ctx, `UPDATE wallet_accounts SET frozen_amount=?,version=version+1,updated_at=? WHERE id=?`, senderFrozen, now, sender.id); err != nil {
				return err
			}
			if _, err := tx.ExecContext(ctx, `UPDATE wallet_accounts SET available_amount=?,version=version+1,updated_at=? WHERE id=?`, recipientAvailable, now, recipient.id); err != nil {
				return err
			}
			if err := r.entry(ctx, tx, appID, transactionID, sender.id, "frozen_debit", amount, senderFrozen, now); err != nil {
				return err
			}
			if err := r.entry(ctx, tx, appID, transactionID, recipient.id, "available_credit", amount, recipientAvailable, now); err != nil {
				return err
			}
		}
		if _, err := tx.ExecContext(ctx, `INSERT INTO wallet_red_packet_claims(app_id,red_packet_id,user_id,amount,created_at) VALUES(?,?,?,?,?)`, appID, packet.ID, userID, amount, now); err != nil {
			return err
		}
		remainingAmount, remainingCount := packet.RemainingAmount-amount, packet.RemainingCount-1
		status := "active"
		if remainingCount == 0 {
			status = "completed"
		}
		if _, err := tx.ExecContext(ctx, `UPDATE wallet_red_packets SET remaining_amount=?,remaining_count=?,status=?,updated_at=? WHERE id=?`, remainingAmount, remainingCount, status, now, packet.ID); err != nil {
			return err
		}
		claim = RedPacketClaim{RedPacketID: packet.ID, OrderNo: orderNo, UserID: userID, Amount: amount, CreatedAt: now}
		receiptChannel := packet.ChannelID
		if packet.ChannelType == 1 {
			receiptChannel = "app" + strconv.FormatUint(appID, 10) + "user" + strconv.FormatUint(packet.SenderID, 10)
		}
		if _, err := enqueueChatMessage(ctx, tx, appID, userID, receiptChannel, packet.ChannelType, 5103, map[string]any{"order_no": orderNo, "status": "claimed", "packet_sender_id": packet.SenderID, "claimant_id": userID, "summary": "已领取红包"}, now); err != nil {
			return err
		}
		if err := enqueuePaymentNotice(ctx, tx, appID, userID, "red_packet_claimed", map[string]any{"order_no": orderNo, "status": "claimed", "amount": amount, "title": "红包已领取"}, now); err != nil {
			return err
		}
		if packet.SenderID != userID {
			if err := enqueuePaymentNotice(ctx, tx, appID, packet.SenderID, "red_packet_claim_receipt", map[string]any{"order_no": orderNo, "status": status, "claimant_id": userID, "title": "红包已被领取"}, now); err != nil {
				return err
			}
		}
		return nil
	})
	return claim, err
}

func (r *SQLRepository) authorizeRedPacketClaim(ctx context.Context, tx *sql.Tx, appID, userID uint64, packet RedPacket) error {
	if packet.ChannelType == 1 {
		prefix := "app" + strconv.FormatUint(appID, 10) + "user"
		recipient, err := strconv.ParseUint(strings.TrimPrefix(packet.ChannelID, prefix), 10, 64)
		if err != nil || recipient != userID {
			return ErrOrderNotFound
		}
		return nil
	}
	var count int
	err := tx.QueryRowContext(ctx, `SELECT COUNT(*) FROM group_members gm JOIN chat_groups g ON g.id=gm.group_id WHERE g.app_id=? AND g.channel_id=? AND gm.user_id=? AND gm.status='active'`, appID, packet.ChannelID, userID).Scan(&count)
	if err != nil {
		return err
	}
	if count != 1 {
		return ErrOrderNotFound
	}
	return nil
}

func claimAmount(packetType string, remaining int64, count uint32) (int64, error) {
	if count == 0 || remaining < int64(count) {
		return 0, ErrOrderState
	}
	if count == 1 {
		return remaining, nil
	}
	if packetType == "normal" {
		return remaining / int64(count), nil
	}
	if packetType != "lucky" && packetType != "designated" {
		return 0, ErrOrderState
	}
	max := remaining - int64(count-1)
	limit := max * 2 / int64(count)
	if limit < 1 {
		limit = 1
	}
	value, err := rand.Int(rand.Reader, big.NewInt(limit))
	if err != nil {
		return 0, err
	}
	return value.Int64() + 1, nil
}

func (r *SQLRepository) RefundExpiredRedPackets(ctx context.Context, limit int) (int, error) {
	rows, err := r.db.QueryContext(ctx, `SELECT order_no FROM wallet_red_packets WHERE status='active' AND expires_at<=NOW(6) ORDER BY id LIMIT ?`, limit)
	if err != nil {
		return 0, err
	}
	orders := []string{}
	for rows.Next() {
		var order string
		if err := rows.Scan(&order); err != nil {
			rows.Close()
			return 0, err
		}
		orders = append(orders, order)
	}
	rows.Close()
	count := 0
	for _, order := range orders {
		ok, err := r.refundRedPacket(ctx, order)
		if err != nil {
			return count, err
		}
		if ok {
			count++
		}
	}
	return count, nil
}

func (r *SQLRepository) refundRedPacket(ctx context.Context, orderNo string) (bool, error) {
	refunded := false
	err := r.db.WithinTx(ctx, nil, func(tx *sql.Tx) error {
		var id, appID, senderID uint64
		var remaining int64
		var status string
		err := tx.QueryRowContext(ctx, `SELECT id,app_id,sender_id,remaining_amount,status FROM wallet_red_packets WHERE order_no=? AND expires_at<=NOW(6) FOR UPDATE`, orderNo).Scan(&id, &appID, &senderID, &remaining, &status)
		if errors.Is(err, sql.ErrNoRows) {
			return nil
		}
		if err != nil {
			return err
		}
		if status != "active" {
			return nil
		}
		now := time.Now().UTC()
		if remaining > 0 {
			account, err := r.lockAccount(ctx, tx, appID, senderID)
			if err != nil {
				return err
			}
			if account.frozen < remaining {
				return ErrOrderState
			}
			transactionID, err := r.createTransaction(ctx, tx, appID, "red_packet_refund", "red_packet", orderNo, remaining, now)
			if err != nil {
				return err
			}
			available, frozen := account.available+remaining, account.frozen-remaining
			if _, err := tx.ExecContext(ctx, `UPDATE wallet_accounts SET available_amount=?,frozen_amount=?,version=version+1,updated_at=? WHERE id=?`, available, frozen, now, account.id); err != nil {
				return err
			}
			if err := r.entry(ctx, tx, appID, transactionID, account.id, "frozen_debit", remaining, frozen, now); err != nil {
				return err
			}
			if err := r.entry(ctx, tx, appID, transactionID, account.id, "available_credit", remaining, available, now); err != nil {
				return err
			}
		}
		_, err = tx.ExecContext(ctx, `UPDATE wallet_red_packets SET remaining_amount=0,remaining_count=0,status='refunded',refunded_at=?,updated_at=? WHERE id=?`, now, now, id)
		if err == nil {
			err = enqueuePaymentNotice(ctx, tx, appID, senderID, "red_packet_refunded", map[string]any{"order_no": orderNo, "status": "refunded", "amount": remaining, "title": "红包已退回"}, now)
		}
		refunded = err == nil
		return err
	})
	return refunded, err
}
