# ТЗ для второго ИИ

## Контекст проекта

Приложение — для преподавателя английского языка и учеников, формат `1 на 1`.

Текущая система звонков и уведомлений уже работает, но исторически на неё наслаивалось много фиксов.  
Задача этого этапа — не чинить legacy ещё раз, а подготовить **новую чистую V2-архитектуру** рядом, в полной изоляции.

## Ключевой принцип

Ты работаешь **только внутри папки `rewrite_v2/`**.

Нельзя:
- выходить за пределы `rewrite_v2/`;
- менять реальные файлы приложения;
- подключать новый код к приложению;
- удалять или переписывать legacy.

## Цель этапа

Подготовить новый каркас для:
1. V2 call state machine
2. V2 incoming/outgoing call lifecycle
3. V2 notification routing
4. V2 backend call transport contracts

Это должен быть именно **foundation rewrite**, а не “ещё один фикс поверх старого”.

---

## Что нужно создать

### 1. Frontend call V2
Папка:
- `rewrite_v2/frontend/lib/call_v2/`

Нужно создать:
- `call_state.dart`
- `call_event.dart`
- `call_session_v2.dart`
- `call_state_machine_v2.dart`
- `call_coordinator_v2.dart`
- `call_ui_intent.dart`
- `README.md`

### 2. Frontend notifications V2
Папка:
- `rewrite_v2/frontend/lib/notifications_v2/`

Нужно создать:
- `notification_event_v2.dart`
- `incoming_call_notification_router_v2.dart`
- `message_notification_router_v2.dart`
- `notification_tap_router_v2.dart`
- `README.md`

### 3. Backend call V2
Папка:
- `rewrite_v2/src/call_v2/`

Нужно создать:
- `call-v2.types.ts`
- `call-v2.events.ts`
- `call-v2.state.ts`
- `call-v2.contract.md`
- `README.md`

---

## Что должно быть внутри

### Frontend V2 call layer
Нужна чистая модель состояний:
- `idle`
- `outgoing`
- `incoming`
- `accepting`
- `connecting`
- `in_call`
- `ending`
- `ended`
- `failed`

Нужны чистые события:
- start outgoing
- receive incoming
- accept
- reject
- remote accepted
- remote rejected
- local end
- remote end
- peer disconnected
- socket lost
- push tapped
- notification cancelled
- timeout no answer
- media connected
- media failed

Нужен coordinator, который:
- не знает про конкретный UI framework deeply;
- только выдаёт `UI intents`;
- не вызывает `Navigator` напрямую;
- не вызывает `setState()` напрямую.

### Frontend V2 notification layer
Нужен отдельный routing для:
- push foreground
- push background
- local notification tap
- incoming call notification
- message notification

Нужно разделить:
- событие транспорта;
- решение “что показать”;
- действие “что открыть”.

### Backend V2 contracts
Пока без реальной интеграции.

Нужно описать:
- какие socket events нужны;
- какие payload у них должны быть;
- какие причины завершения стандартизированы;
- какие acknowledgment события должны существовать;
- как выглядит минимальный lifecycle звонка.

---

## Требования к архитектуре

### Обязательно
- никакой legacy-логики копипастой;
- минимум зависимостей;
- понятные имена;
- маленькие файлы;
- без хаоса “всё в одном сервисе”.

### Нельзя
- писать код “на всякий случай”;
- тащить старые костыли;
- делать UI-реализацию экранов;
- делать интеграцию с реальными socket/push сервисами на этом этапе.

---

## Ожидаемый результат этапа

Нужен не рабочий прод-модуль, а **чистый, понятный V2 blueprint**, который потом можно будет подключать поэтапно.

Результат должен быть таким, чтобы следующий этап мог сделать:
1. адаптер к реальному socket service;
2. адаптер к реальному push service;
3. feature flag;
4. постепенное переключение со старого flow.

---

## В конце работы

Нужно выдать:
- список созданных файлов;
- короткое описание роли каждого файла;
- какие состояния и события заложены;
- что будет следующим этапом интеграции.
