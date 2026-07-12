package media

import (
	"bim/server/internal/modules/identity"
	"bim/server/internal/platform/httpx"
	"github.com/go-chi/chi/v5"
	"net/http"
	"strconv"
)

type Handler struct{ service *Service }

func NewHandler(s *Service) *Handler { return &Handler{service: s} }
func (h *Handler) Routes() http.Handler {
	r := chi.NewRouter()
	r.Post("/", h.upload)
	r.Get("/{id}", h.resolve)
	return r
}
func (h *Handler) PublicRoutes() http.Handler {
	r := chi.NewRouter()
	r.Get("/{id}/content", h.content)
	return r
}
func p(w http.ResponseWriter, r *http.Request) (identity.Principal, bool) {
	v, ok := identity.PrincipalFromContext(r.Context())
	if !ok {
		httpx.Error(w, r, 401, "UNAUTHORIZED", "请先登录")
	}
	return v, ok
}
func assetID(w http.ResponseWriter, r *http.Request) (uint64, bool) {
	id, e := strconv.ParseUint(chi.URLParam(r, "id"), 10, 64)
	if e != nil {
		httpx.Error(w, r, 400, "INVALID_ASSET_ID", "文件编号无效")
		return 0, false
	}
	return id, true
}
func (h *Handler) upload(w http.ResponseWriter, r *http.Request) {
	u, ok := p(w, r)
	if !ok {
		return
	}
	r.Body = http.MaxBytesReader(w, r.Body, 210<<20)
	if err := r.ParseMultipartForm(8 << 20); err != nil {
		httpx.Error(w, r, 400, "UPLOAD_INVALID", "上传内容无效")
		return
	}
	file, header, err := r.FormFile("file")
	if err != nil {
		httpx.Error(w, r, 400, "UPLOAD_INVALID", "请选择文件")
		return
	}
	defer file.Close()
	asset, err := h.service.Upload(r.Context(), u.User.AppID, u.User.ID, r.FormValue("kind"), file, header)
	if err != nil {
		httpx.Error(w, r, 400, "UPLOAD_REJECTED", err.Error())
		return
	}
	httpx.JSON(w, 201, httpx.Envelope{Code: "OK", Message: "上传成功", Data: asset, RequestID: httpx.RequestID(r.Context())})
}
func (h *Handler) resolve(w http.ResponseWriter, r *http.Request) {
	u, ok := p(w, r)
	if !ok {
		return
	}
	id, ok := assetID(w, r)
	if !ok {
		return
	}
	asset, err := h.service.Resolve(r.Context(), u.User.AppID, u.User.ID, id)
	if err != nil {
		httpx.Error(w, r, 404, "ASSET_NOT_FOUND", "文件不存在或无权访问")
		return
	}
	httpx.OK(w, r, asset)
}
func (h *Handler) content(w http.ResponseWriter, r *http.Request) {
	id, ok := assetID(w, r)
	if !ok {
		return
	}
	expires, e := strconv.ParseInt(r.URL.Query().Get("expires"), 10, 64)
	if e != nil {
		httpx.Error(w, r, 403, "ASSET_URL_INVALID", "下载地址已失效")
		return
	}
	path, mime, err := h.service.Open(id, expires, r.URL.Query().Get("signature"))
	if err != nil {
		httpx.Error(w, r, 403, "ASSET_URL_INVALID", "下载地址已失效")
		return
	}
	w.Header().Set("Content-Type", mime)
	w.Header().Set("Cache-Control", "private, max-age=900, immutable")
	http.ServeFile(w, r, path)
}
