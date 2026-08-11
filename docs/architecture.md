# Детальные архитектурные диаграммы

## 1. Полная диаграмма компонентов системы

```mermaid
flowchart TB
    subgraph Client["Flutter Client"]
        direction TB
        LS["Login Screen"]
        AS["Admin Screen"]
        US["User Screen"]
        AP["Auth Provider"]
        CP["Chat Provider"]
        ASvc["Auth Service"]
        ApiSvc["API Service Dio"]
        SSvc["Socket Service"]
    end

    subgraph Server["NestJS Server :3000"]
        direction TB
        AC["Auth Controller\nPOST /auth/login"]
        ASrv["Auth Service\nlogin + validateUser"]
        JS["JWT Strategy\nPassport"]
        
        UC["Users Controller\nCRUD + Status"]
        USrv["Users Service\nbusiness logic"]
        
        CC["Chat Controller\nHTTP endpoints"]
        CSrv["Chat Service\nmessage logic"]
        CG["Chat Gateway\nSocket.IO"]
        
        PS["Prisma Service"]
    end

    subgraph DB["Database Layer"]
        PClient["Prisma Client"]
        SQLite["SQLite / PostgreSQL"]
    end

    LS --> AP
    AS --> CP
    US --> CP
    AP --> ASvc
    CP --> ApiSvc
    CP --> SSvc
    ASvc --> ApiSvc
    ApiSvc --> AC
    ApiSvc --> UC
    ApiSvc --> CC
    SSvc --> CG
    AC --> ASrv
    ASrv --> PS
    JS --> ASrv
    UC --> USrv
    USrv --> PS
    CC --> CSrv
    CG --> CSrv
    CSrv --> PS
    PS --> PClient
    PClient --> SQLite
```

---

## 2. Диаграмма последовательности аутентификации

```mermaid
sequenceDiagram
    participant U as User
    participant LS as LoginScreen
    participant AP as AuthProvider
    participant ASvc as AuthService
    participant Api as ApiService
    participant AC as AuthController
    participant ASrv as AuthService
    participant PS as PrismaService
    participant DB as Database

    U->>LS: Вводит логин/пароль
    LS->>AP: login(login, password)
    AP->>ASvc: login(login, password)
    ASvc->>Api: POST /auth/login
    Api->>AC: HTTP Request
    AC->>ASrv: login(dto)
    ASrv->>PS: findUnique(login)
    PS->>DB: SELECT * FROM User WHERE login = ?
    DB-->>PS: User data
    PS-->>ASrv: User
    
    alt User not found
        ASrv-->>AC: UnauthorizedException
        AC-->>Api: 401
        Api-->>ASvc: Error
        ASvc-->>AP: Exception
        AP-->>LS: error = 'Ошибка входа'
    else User blocked/archived
        ASrv-->>AC: UnauthorizedException
        AC-->>Api: 401
    else Valid credentials
        ASrv->>ASrv: bcrypt.compare(password, hash)
        ASrv->>ASrv: JWT.sign(payload)
        ASrv-->>AC: { accessToken, user }
        AC-->>Api: 200 JSON
        Api-->>ASvc: Response
        ASvc->>ASvc: save token to SecureStorage
        ASvc-->>AP: { accessToken, user }
        AP->>AP: set currentUser
        AP->>SSvc: connect(token)
        AP-->>LS: success = true
        LS->>LS: Navigate to /admin or /user
    end
```

---

## 3. Диаграмма последовательности отправки сообщения

```mermaid
sequenceDiagram
    participant U as User
    participant US as UserScreen
    participant CP as ChatProvider
    participant Api as ApiService
    participant CC as ChatController
    participant CSrv as ChatService
    participant PS as PrismaService
    participant DB as Database
    participant CG as ChatGateway
    participant SS as SocketService

    U->>US: Вводит текст + нажимает Отправить
    US->>CP: sendMessage(text, receiverId)
    CP->>Api: POST /chat { text, receiverId }
    Api->>CC: HTTP Request
    CC->>CSrv: createMessage(senderId, role, dto)
    CSrv->>PS: findUnique(sender)
    PS-->>CSrv: Sender
    CSrv->>PS: resolveReceiver(role, receiverId)
    PS-->>CSrv: Receiver
    CSrv->>PS: create(message)
    PS->>DB: INSERT INTO Message
    DB-->>PS: Message
    PS-->>CSrv: Message
    CSrv-->>CC: Message
    CC-->>Api: 201 JSON
    Api-->>CP: Response
    CP-->>US: UI update

    Note over CG,SS: Real-time delivery via WebSocket
    CG->>CG: emitToUser(senderId, message:new)
    CG->>CG: emitToUser(receiverId, message:new)
    CG->>CSrv: markDelivered(messageId)
    CG->>CG: emitToUser(senderId, message:delivered)
    CG->>CG: emitToUser(receiverId, message:delivered)
    SS-->>CP: message:new event
    CP->>CP: add message to list
    CP-->>US: UI update
```

---

## 4. Диаграмма классов Backend

```mermaid
classDiagram
    class PrismaService {
        +onModuleInit()
        +onModuleDestroy()
    }

    class AuthService {
        +login(dto: LoginDto) AuthResponseDto
        +validateUser(userId: number) User
    }

    class AuthController {
        +login(dto: LoginDto) AuthResponseDto
    }

    class JwtStrategy {
        +validate(payload) User
    }

    class JwtAuthGuard {
        +canActivate() boolean
    }

    class RolesGuard {
        +canActivate() boolean
    }

    class UsersService {
        +create(dto: CreateUserDto) User
        +findAll() User[]
        +findOne(id: number) User
        +update(id: number, dto: UpdateUserDto) User
        +block(id: number) User
        +unblock(id: number) User
        +archive(id: number) User
        +restore(id: number) User
    }

    class UsersController {
        +create(dto: CreateUserDto) User
        +findAll() User[]
        +findOne(id: number) User
        +update(id: number, dto: UpdateUserDto) User
        +block(id: number) User
        +unblock(id: number) User
        +archive(id: number) User
        +restore(id: number) User
    }

    class ChatService {
        +createMessage(senderId, senderRole, dto) Message
        +findAll() Message[]
        +findByUser(userId) Message[]
        +deleteMessage(id) Message
        +markDelivered(id) Message
        +markRead(id, readerId) Message
    }

    class ChatController {
        +create(dto, user) Message
        +findMy(user) Message[]
        +findAll() Message[]
        +findByUser(userId) Message[]
        +delete(id) Message
    }

    class ChatGateway {
        +handleConnection(client)
        +handleDisconnect(client)
        +handleSendMessage(client, payload)
        +handleReadMessage(client, payload)
    }

    AuthController --> AuthService
    JwtStrategy --> AuthService
    UsersController --> UsersService
    ChatController --> ChatService
    ChatGateway --> ChatService
    ChatGateway --> JwtService
    ChatGateway --> PrismaService
    AuthService --> PrismaService
    UsersService --> PrismaService
    ChatService --> PrismaService
    UsersController ..|> JwtAuthGuard
    UsersController ..|> RolesGuard
    ChatController ..|> JwtAuthGuard
    ChatController ..|> RolesGuard
```

---

## 5. Диаграмма классов Frontend

```mermaid
classDiagram
    class User {
        +int id
        +String fio
        +int age
        +String login
        +String role
        +String status
        +fromJson() User
        +toJson() Map
        +isAdmin bool
        +isActive bool
        +isBlocked bool
        +isArchived bool
    }

    class Message {
        +int? id
        +int senderId
        +int receiverId
        +String content
        +DateTime? createdAt
        +bool isRead
        +fromJson() Message
        +toJson() Map
    }

    class ApiService {
        -Dio _dio
        -FlutterSecureStorage _storage
        +get() Response
        +post() Response
        +put() Response
        +delete() Response
    }

    class AuthService {
        +login() Map
        +setToken()
        +getToken()
        +logout()
        +isLoggedIn() bool
    }

    class SocketService {
        -IO.Socket? _socket
        +connect(token)
        +sendMessage(text, userId)
        +onNewMessage(callback)
        +disconnect()
    }

    class AuthProvider {
        -User? _currentUser
        -bool _isLoading
        -String? _error
        +checkAuth() bool
        +login() bool
        +logout()
        +clearError()
    }

    class ChatProvider {
        -List~Message~ _messages
        -List~User~ _users
        -User? _selectedUser
        +loadUsers()
        +loadMessages()
        +loadUserMessages(userId)
        +selectUser(user)
        +sendMessage(text, userId)
        +deleteMessage(id)
        +addMessage(message)
        +clearError()
    }

    class LoginScreen
    class AdminScreen
    class UserScreen

    AuthProvider --> AuthService
    AuthProvider --> SocketService
    ChatProvider --> ApiService
    ChatProvider --> SocketService
    LoginScreen --> AuthProvider
    AdminScreen --> ChatProvider
    AdminScreen --> AuthProvider
    AdminScreen --> ApiService
    UserScreen --> ChatProvider
    UserScreen --> AuthProvider
```

---

## 6. ER-диаграмма базы данных (детальная)

```mermaid
erDiagram
    User {
        int id PK "autoincrement"
        string fio "NOT NULL"
        int age "NOT NULL"
        string login UK "NOT NULL"
        string passwordHash "NOT NULL"
        enum Role role "default USER"
        enum UserStatus status "default ACTIVE"
        datetime createdAt "default now"
        datetime updatedAt "@updatedAt"
    }

    Message {
        int id PK "autoincrement"
        int senderId FK "NOT NULL"
        int receiverId FK "NOT NULL"
        string text "NOT NULL"
        enum MessageStatus status "default SENT"
        datetime createdAt "default now"
        datetime updatedAt "@updatedAt"
    }

    User ||--o{ Message : "senderId > id"
    User ||--o{ Message : "receiverId > id"

    User {
        int id PK
    }
    User {
        string login UK
    }
    User {
        enum Role role
    }
    User {
        enum UserStatus status
    }
    User {
        datetime createdAt
    }

    Message {
        int senderId
    }
    Message {
        int receiverId
    }
    Message {
        enum MessageStatus status
    }

    %% Indexes
    %% User: @@index([role], [status], [createdAt])
    %% Message: @@index([senderId, createdAt], [receiverId, createdAt], [status])
```

---

## 7. Диаграмма состояний пользователя

```mermaid
stateDiagram-v2
    [*] --> ACTIVE: create user
    ACTIVE --> BLOCKED: admin blocks
    ACTIVE --> ARCHIVED: admin archives
    BLOCKED --> ACTIVE: admin unblocks
    BLOCKED --> ARCHIVED: admin archives
    ARCHIVED --> ACTIVE: admin restores
    BLOCKED --> [*]: delete user
    ACTIVE --> [*]: delete user
    ARCHIVED --> [*]: delete user
```

---

## 8. Диаграмма состояний сообщения

```mermaid
stateDiagram-v2
    [*] --> SENT: message created
    SENT --> DELIVERED: receiver online
    SENT --> SENT: receiver offline
    DELIVERED --> READ: receiver opens
    SENT --> [*]: admin deletes
    DELIVERED --> [*]: admin deletes
    READ --> [*]: admin deletes
```

---

## 9. Диаграмма развёртывания

```mermaid
flowchart LR
    subgraph Dev["Development Environment"]
        subgraph BE["NestJS Backend"]
            API["REST API :3000"]
            WS["WebSocket :3000"]
        end
        DBDev["SQLite\nfile-based"]
    end

    subgraph Prod["Production Environment"]
        subgraph BEProd["NestJS Backend"]
            APIProd["REST API :3000"]
            WSProd["WebSocket :3000"]
        end
        DBProd["PostgreSQL"]
        Redis["Redis\nfor Socket.IO"]
        MinIO["MinIO\nfile storage"]
    end

    subgraph Client["Client Devices"]
        Android["Android App"]
        iOS["iOS App"]
        Web["Web Browser"]
    end

    Dev --> DBDev
    Prod --> DBProd
    Prod --> Redis
    Prod --> MinIO
    Client --> APIProd
    Client --> WSProd
    Client --> API
    Client --> WS
```

---

## 10. Диаграмма пакетов (NestJS модули)

```mermaid
flowchart TB
    subgraph AppModule["AppModule root"]
        direction TB
        PM["PrismaModule\nGlobal"]
        AM["AuthModule"]
        UM["UsersModule"]
        CM["ChatModule"]
    end

    PM --> PS["PrismaService"]
    
    subgraph AM_["AuthModule"]
        AC["AuthController"]
        AS["AuthService"]
        JS["JwtStrategy"]
        JG["JwtAuthGuard"]
        RG["RolesGuard"]
    end

    subgraph UM_["UsersModule"]
        UC["UsersController"]
        US["UsersService"]
    end

    subgraph CM_["ChatModule"]
        CC["ChatController"]
        CS["ChatService"]
        CG["ChatGateway"]
    end

    AM_ --> AM
    UM_ --> UM
    CM_ --> CM

    AM_ -->|imports| JwtModule
    AM_ -->|imports| PassportModule
    CM_ -->|imports| AM_
    
    AC --> AS
    UC --> US
    CC --> CS
    CG --> CS
    CG --> JwtService
    CG --> PS
    
    AS --> PS
    US --> PS
    CS --> PS
    JS --> AS