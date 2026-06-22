/// V2 состояния звонка.
///
/// Каждое состояние имеет категорию [category] и человекочитаемое [label].
/// Категория позволяет coordinator'у принимать решения на высоком уровне,
/// не привязываясь к конкретному состоянию.
enum CallStateV2 {
  idle('idle', CallStateCategoryV2.idle, 'Нет звонка'),
  outgoing('outgoing', CallStateCategoryV2.active, 'Исходящий звонок'),
  incoming('incoming', CallStateCategoryV2.active, 'Входящий звонок'),
  accepting('accepting', CallStateCategoryV2.active, 'Принятие звонка'),
  connecting('connecting', CallStateCategoryV2.active, 'Установка соединения'),
  inCall('in_call', CallStateCategoryV2.active, 'Разговор'),
  ending('ending', CallStateCategoryV2.ending, 'Завершение звонка'),
  ended('ended', CallStateCategoryV2.final_, 'Звонок завершён'),
  failed('failed', CallStateCategoryV2.final_, 'Ошибка звонка');

  final String value;
  final CallStateCategoryV2 category;
  final String label;

  const CallStateV2(this.value, this.category, this.label);

  bool get isActive => category == CallStateCategoryV2.active;
  bool get isFinal => category == CallStateCategoryV2.final_;
  bool get isIdle => this == CallStateV2.idle;
}

/// Категория состояния для высокоуровневой логики.
enum CallStateCategoryV2 {
  idle,
  active,
  ending,
  final_,
}
