package serviceaccount

type Account struct {
	ID            uint64 `json:"id"`
	Code          string `json:"code"`
	Name          string `json:"name"`
	AvatarAssetID uint64 `json:"avatar_asset_id"`
	Description   string `json:"description"`
	InputEnabled  bool   `json:"input_enabled"`
	Muted         bool   `json:"muted"`
	Subscribed    bool   `json:"subscribed"`
	Menu          any    `json:"menu"`
}
