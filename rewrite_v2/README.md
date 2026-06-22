# Rewrite V2 Workspace

Это изолированная песочница для частичного rewrite звонков и push-уведомлений.

Цель:
- не ломать рабочий legacy-код;
- не трогать продовую ветку;
- не менять существующие файлы приложения на этом этапе;
- проектировать и писать новый V2-код только внутри `rewrite_v2/`.

Что здесь лежит:
- `TASK_FOR_SECOND_AI.md` — основное ТЗ;
- `SCOPE.md` — жёсткие границы;
- `frontend/lib/call_v2/` — новый frontend call-flow;
- `frontend/lib/notifications_v2/` — новый frontend notification-flow;
- `src/call_v2/` — новый backend call-flow.

Важно:
- это staging-area;
- код здесь пока не подключён к основному приложению;
- интеграция в реальный проект будет отдельным этапом.
