# BIM 客户端 UI 重构软件架构图

本文档用于重做 UI 前统一客户端架构认知。目标是把界面、状态、缓存、实时 IM、业务接口边界拆清楚，避免 UI 改版时破坏即时通信链路。

## 1. 总体架构

```mermaid
flowchart TB
  User[用户]

  subgraph FlutterApp[BIM Flutter 客户端]
    subgraph UILayer[UI 层]
      AuthUI[登录/注册]
      MainShell[主框架: 消息/通讯录/发现/我的]
      ChatUI[私聊/群聊页面]
      PickerUI[图片/视频/文件选择器]
      PayUI[红包/转账交互]
      LogsUI[本地日志查看]
    end

    subgraph StateLayer[状态与业务编排层]
      SessionController[SessionController]
    end

    subgraph IMLayer[IM 业务层]
      BusinessIM[BusinessImService]
      ChatFeature[ChatFeatureService]
      GatewayClient[GatewayStreamClient]
    end

    subgraph CoreLayer[基础能力层]
      ApiClient[ApiClient]
      Signer[ApiSigner]
      Crypto[ApiPayloadCrypto]
      Cache[MMKV: ImCacheStore/SessionStore/SecureCache]
      Logger[AppLogger]
    end
  end

  subgraph Server[服务端]
    TP8[TP8 业务 API]
    Gateway[BIM Gateway HTTPS Stream]
    Redis[Redis Stream/PubSub]
    WK[WuKongIM]
  end

  User --> UILayer
  UILayer --> SessionController
  SessionController --> BusinessIM
  SessionController --> ChatFeature
  BusinessIM --> GatewayClient
  BusinessIM --> Cache
  ChatFeature --> ApiClient
  SessionController --> ApiClient
  ApiClient --> Signer
  ApiClient --> Crypto
  ApiClient --> TP8
  GatewayClient --> Gateway
  Gateway --> Redis
  TP8 --> Redis
  TP8 --> WK
  WK --> TP8
  Cache --> UILayer
  Logger --> LogsUI
```

## 2. UI 页面模块图

```mermaid
flowchart LR
  App[BimApp]
  App --> Auth[AuthPage]
  App --> Home[HomePage/MainShell]

  Home --> Messages[消息]
  Home --> Contacts[通讯录]
  Home --> Discover[发现]
  Home --> Mine[我的]

  Messages --> ConversationList[会话列表]
  Messages --> ChatPage[聊天页]

  Contacts --> FriendList[好友列表]
  Contacts --> GroupEntry[群聊入口]
  Contacts --> FriendRequests[新的朋友]
  Contacts --> AddFriend[添加好友]

  ChatPage --> ChatHeader[顶部: 昵称/人数/在线]
  ChatPage --> MessageList[消息列表]
  ChatPage --> Composer[输入框]
  ChatPage --> ToolPanel[工具面板]
  ChatPage --> ActionSheet[消息操作]

  ToolPanel --> MediaPicker[图片/视频/文件]
  ToolPanel --> RedPacket[红包]
  ToolPanel --> Transfer[转账]
  ToolPanel --> ContactCard[名片]
```

## 3. 实时 IM 数据流

```mermaid
sequenceDiagram
  participant UI as Chat UI
  participant SC as SessionController
  participant IM as BusinessImService
  participant GW as GatewayStreamClient
  participant API as TP8 API
  participant S as Gateway/WuKongIM
  participant C as MMKV Cache

  UI->>SC: 发送消息
  SC->>IM: sendBusinessMessage
  IM->>C: 写入发送中状态
  IM->>API: 加密提交 im_person_send / im_group_send
  API->>S: 业务校验后调用 WuKongIM
  S-->>GW: Gateway frame
  GW-->>IM: 解密 frame
  IM->>C: upsert 消息/会话
  IM-->>SC: messageEvents
  SC-->>UI: notifyListeners
  UI->>UI: 局部刷新气泡状态
```

## 4. 在线状态数据流

```mermaid
sequenceDiagram
  participant WK as WuKongIM
  participant API as TP8 Webhook
  participant Redis as Redis Stream
  participant GW as BIM Gateway
  participant Client as Flutter Client
  participant Cache as MMKV
  participant UI as 通讯录/聊天页

  WK->>API: user.onlinestatus
  API->>API: 更新在线缓存/在线事件表
  API->>Redis: 写入 type=presence
  API->>Redis: PUBLISH im:notify
  Redis-->>GW: 通知目标用户
  GW-->>Client: presence frame
  Client->>Cache: 更新好友在线字段
  Client-->>UI: presenceEvents/notifyListeners
  UI->>UI: 实时显示在线/离线
```

## 5. 缓存边界

```mermaid
flowchart TB
  subgraph Cache[MMKV 缓存]
    Session[登录态/设备标识]
    Conversations[会话列表]
    Messages[私聊/群聊消息]
    Friends[好友列表/在线状态]
    Groups[群列表]
    Profiles[头像/昵称资料]
    Drafts[输入草稿]
    ReadMarkers[已读游标]
    GatewayCursor[Gateway cursor]
  end

  UI[UI 页面] --> Cache
  Business[业务层] --> Cache
  Cache --> UI
```

缓存原则：

- UI 优先读取本地缓存，避免进入页面闪屏。
- 业务接口返回后只更新对应模块缓存，不跨模块乱写。
- 实时消息、撤回、已读、红包、转账、在线状态都必须通过事件更新 UI。
- 开发调试期不做旧缓存迁移；发现非法缓存直接过滤或清数据重测。

## 6. UI 重构建议目录

当前 `lib/src/features/home/home_page.dart` 过大，重做 UI 时建议拆成：

```text
lib/src/features/home/
  home_page.dart
  tabs/
    messages_tab.dart
    contacts_tab.dart
    discover_tab.dart
    mine_tab.dart
  chat/
    chat_page.dart
    chat_header.dart
    message_list.dart
    message_bubble.dart
    composer_bar.dart
    tool_panel.dart
  contacts/
    contacts_page.dart
    friend_tile.dart
    group_list_page.dart
    friend_requests_page.dart
  common/
    avatar.dart
    section_header.dart
    empty_row.dart
    media_preview.dart
```

拆分规则：

- 页面只负责布局和交互。
- 状态统一走 `SessionController`。
- IM 逻辑只放 `BusinessImService` 和 `ChatFeatureService`。
- API 加密、签名、请求只放 `ApiClient`。
- 缓存只通过 `ImCacheStore/SessionStore/SecureCache`。

## 7. UI 重做约束

- 主界面保持：消息、通讯录、发现、我的。
- 风格简洁，不做阴影，不做卡片堆叠，不做大圆角。
- 聊天页必须保持即时刷新，不允许用页面重载代替局部更新。
- 消息发送状态：发送中转圈，成功单勾，已读双勾，失败感叹号可重发。
- 红包、转账、图片、视频、文件要先显示本地发送中状态，再根据服务端确认更新。
- 好友在线/离线必须由 Gateway presence 实时事件驱动。
- 群人数、群在线人数、禁言状态要显示真实服务端数据，不做假数据。

## 8. UI 重构验收点

- 冷启动能先显示缓存会话，再同步服务端。
- 进入私聊/群聊直接停在底部，不出现跳动。
- 输入法弹起时消息列表跟随顶起，不闪到顶部。
- 发送消息后输入框立即清空，气泡立即出现发送中。
- 接收方在聊天页、后台恢复、会话列表三种场景都能实时看到消息。
- 好友上线/离线不刷新页面也能更新。
- 清除聊天记录后，服务端历史不会重新拉回已清除内容。
- 红包/转账领取后只更新原消息，不创建新会话。

## 9. 当前拆分落地状态

已按第一阶段完成 `home_page.dart` 结构拆分：主入口只保留首页 Shell、底部导航、标题状态和模块 `part` 声明；消息、通讯录、发现、我的、聊天页、聊天组件、联系人页面和通用组件已拆到独立目录。

第一阶段使用 Dart `part` 保持原有私有方法和状态可见性，目的是先降低单文件复杂度且不改变 IM 行为。后续重做 UI 时，再逐步把稳定组件升级为独立 widget 文件和公开模型，避免一次性重构破坏实时消息、缓存和发送状态。

当前目录边界：

- `tabs/`：消息、通讯录、发现、我的四个首页 Tab。
- `chat/`：聊天页、聊天头部、消息列表、消息气泡、输入栏、工具面板、消息格式化。
- `contacts/`：搜索、加好友、好友申请、群聊管理、私聊操作页面和联系人 helper。
- `common/`：头像、列表项、媒体预览、通用状态块、导航 helper、基础 map/helper。
