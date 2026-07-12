package messaging

import "fmt"

const (
	ChannelPerson uint8 = 1
	ChannelGroup  uint8 = 2

	TypeText   uint32 = 1
	TypeImage  uint32 = 2
	TypeVoice  uint32 = 3
	TypeVideo  uint32 = 4
	TypeFile   uint32 = 5
	TypeCMD    uint32 = 99
	TypeRecall uint32 = 1006

	TypeTransfer          uint32 = 5101
	TypeRedPacket         uint32 = 5102
	TypeRedPacketReceived uint32 = 5103
	TypeTransferReceived  uint32 = 5104
	TypeEmoji             uint32 = 5201
	TypeGIF               uint32 = 5202
	TypeSticker           uint32 = 5203
	TypeContactCard       uint32 = 5207
	TypeCall              uint32 = 5301
	TypeGroupEvent        uint32 = 5401
	TypeServiceNotice     uint32 = 5501
)

type Header struct {
	NoPersist int `json:"no_persist"`
	RedDot    int `json:"red_dot"`
	SyncOnce  int `json:"sync_once"`
}

func HeaderFor(contentType uint32, system bool) (Header, error) {
	if contentType == TypeCMD {
		return Header{NoPersist: 1, RedDot: 1, SyncOnce: 1}, nil
	}
	if system && contentType <= 1000 {
		return Header{}, fmt.Errorf("system message type must be greater than 1000")
	}
	return Header{NoPersist: 0, RedDot: 1, SyncOnce: 0}, nil
}

func ValidateContentType(contentType uint32) error {
	switch contentType {
	case TypeText, TypeImage, TypeVoice, TypeVideo, TypeFile, TypeCMD, TypeRecall,
		TypeTransfer, TypeRedPacket, TypeRedPacketReceived, TypeTransferReceived,
		TypeEmoji, TypeGIF, TypeSticker, TypeContactCard, TypeCall:
		return nil
	case TypeGroupEvent, TypeServiceNotice:
		return nil
	default:
		return fmt.Errorf("unsupported message type %d", contentType)
	}
}
