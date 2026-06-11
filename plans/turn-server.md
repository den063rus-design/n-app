# TURN-сервер для WebRTC — план внедрения

## Статус
🟡 **Не начато.** В проекте настроен только STUN-сервер (`stun:stun.l.google.com:19302`).
TURN-сервер отсутствует.

## Текущая конфигурация

**Файл:** [`frontend/lib/services/call_service.dart`](frontend/lib/services/call_service.dart):192-196

```dart
final config = {
  'iceServers': [
    {'urls': 'stun:stun.l.google.com:19302'},
  ],
};
```

## Проблема
- STUN работает только для простых NAT (полный конус, restricted cone)
- При симметричном NAT, корпоративных файрволах или мобильных сетях P2P соединение не устанавливается
- TURN-сервер ретранслирует трафик через себя, гарантируя соединение в любых сетях

## План внедрения

### Этап 1: Развернуть TURN-сервер (coturn)
1. Установить `coturn` на сервер
2. Настроить конфигурацию:
   - `listening-port=3478`
   - `fingerprint`
   - `lt-cred-mech`
   - `user=n-app:YOUR_TURN_PASSWORD`
   - `realm=n-app.local`
   - `total-quota=100`
3. Открыть порты 3478 (TCP/UDP) и 49152-65535 (UDP relay) в файрволе

### Этап 2: Обновить конфигурацию ICE на фронтенде
```dart
final config = {
  'iceServers': [
    {'urls': 'stun:stun.l.google.com:19302'},
    {
      'urls': 'turn:YOUR_SERVER_IP:3478',
      'username': 'n-app',
      'credential': 'YOUR_TURN_PASSWORD',
    },
  ],
};
```

### Этап 3: Вынести конфигурацию ICE в переменные окружения
- Добавить `TURN_URL`, `TURN_USERNAME`, `TURN_CREDENTIAL` в `.env`
- Передавать через API config или build-time переменные

### Этап 4: Тестирование
- Проверить звонки через мобильный интернет (4G/5G)
- Проверить звонки через корпоративный VPN
- Проверить звонки при отключенном STUN (только TURN)

## Альтернативы
- **Twilio Network Traversal Service** — платный, не нужно разворачивать сервер
- **Xirsys** — платный, глобальная инфраструктура
- **Cloudflare Calls** — новый сервис, в стадии беты