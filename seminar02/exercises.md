# Семинар 2 · Упражнения по нормализации (дома)

Не оцениваются. Разберём на семинаре 3; похожие будут в письменной работе на неделе 8.
Ответы пишите прямо здесь.

## 1. Рейсы

Таблица `flight(flight_no, date, aircraft, aircraft_seats, captain, captain_licence, route_from, route_to, route_distance)`.

а) Выпишите функциональные зависимости.
б) Найдите ключ (или возможные ключи).
в) Какие аномалии возникнут при: замене самолёта на рейсе; изменении номера лицензии командира; отмене всех рейсов по маршруту?
г) Приведите к 3NF: перечислите таблицы с ключами.

Решение:

### а–б) Зависимости и ключ

Предположения: `aircraft` — уникальный борт, а не модель самолёта; `captain` — уникальный идентификатор командира, не просто ФИО; номер рейса повторяется по датам, но в одну дату имеет один вылет. Расстояние определяется упорядоченной парой аэропортов при принятой модели маршрута.

- `(flight_no, date) → aircraft, captain, route_from, route_to`.
- `aircraft → aircraft_seats`.
- `captain → captain_licence` (одна текущая лицензия на командира).
- `(route_from, route_to) → route_distance`.

Кандидатный ключ — `(flight_no, date)`. В этой модели нет других гарантированных ключей. Если `captain` — ФИО, требуется `captain_id`; если возможны несколько вылетов одного номера в день — `departure_at` или идентификатор вылета. Зависимость `flight_no → route_from, route_to` без дополнительных условий не предполагается: маршрут номера рейса может меняться.

### в) Аномалии

При замене самолёта нужно одновременно поменять борт и число кресел; частичное обновление даёт противоречие. Число кресел одного борта повторяется во всех рейсах, поэтому изменение конфигурации требует массового обновления. Номер лицензии командира повторяется в каждом рейсе: часть записей может остаться со старой лицензией. Удаление всех рейсов по маршруту удаляет и единственное описание расстояния маршрута. Без рейса нельзя отдельно зарегистрировать новый борт, командира или маршрут — аномалия вставки.

### г) Декомпозиция в 3NF

| Таблица | PK | Остальные атрибуты / FK |
|---|---|---|
| `aircraft` | `aircraft` | `aircraft_seats` |
| `captain` | `captain` | `captain_licence` |
| `route` | `(route_from, route_to)` | `route_distance` |
| `flight` | `(flight_no, date)` | `aircraft` FK, `captain` FK, `(route_from, route_to)` составной FK |

Каждая указанная зависимость хранится в отношении, где её детерминант — ключ. Обратное соединение по PK/FK восстанавливает рейсы без потерь; зависимости сохраняются. Историю конфигурации самолётов и лицензий при необходимости нужно версионировать с периодами действия, иначе такая схема описывает только текущие справочники.

## 2. Телеметрия «плоско»

Таблица `reading(sensor_tag, unit_code, station_name, ts, value, unit_of_measure)` — 10⁹ строк, только вставки.

а) Какие аномалии возникнут, когда агрегат перевезут на другую площадку? Когда датчик перекалибруют в другие единицы?
б) Что нужно вынести в отдельные таблицы?
в) Какую денормализацию вы бы всё же оставили ради скорости чтения и почему? Как будете её синхронизировать?

Решение:

### а) Аномалии и время

При предположении глобально уникального `sensor_tag`: `sensor_tag → unit_code, unit_of_measure`, `unit_code → station_name`, `(sensor_tag, ts) → value`. Если tag уникален лишь внутри агрегата, естественный ключ датчика — `(unit_code, sensor_tag)`, а чтения — `(unit_code, sensor_tag, ts)`.

После переезда агрегата новые строки имеют новую площадку, старые — прежнюю. Это допустимые исторические факты только при явной семантике «площадка в момент измерения»; они не являются единым текущим справочником. Переписывание миллиарда старых строк ради текущего размещения уничтожает историю. Аналогично новая калибровка в другой единице не должна менять смысл старых значений: нельзя просто обновить `unit_of_measure` без преобразования `value`. Повторяющиеся метаданные вызывают несогласованность, дорогие массовые обновления и невозможность хранить агрегат без измерений.

### б) Отдельные сущности

- `station(id PK, code UNIQUE, name)` — площадка; имя само по себе не гарантирует уникальность.
- `unit(id PK, code UNIQUE, station_id FK)` — агрегат, его текущее размещение.
- `metric_type(id PK, code UNIQUE, quantity, unit_of_measure)` — семантика и единица метрики.
- `sensor(id PK, sensor_tag UNIQUE, unit_id FK, metric_type_id FK)` — канал.
- `reading(id identity PK, sensor_id FK, ts timestamptz, value numeric, UNIQUE(sensor_id, ts))` — измерение.

При необходимости исторических ответов: `unit_placement(unit_id, station_id, valid_from, valid_to)` и версии калибровки/единиц каналов с непересекающимися периодами. Измерение должно однозначно ссылаться на версию калибровки либо соединяться с ней по своему `ts`. Альтернатива — преобразовать все исходные значения в одну каноническую единицу, сохраняя исходные значения и происхождение преобразования отдельно.

В проекте соответствующая цепочка — `node_group → node → component → metric_source → telemetry`. Тип метрики задаёт единицу измерения. Метаданные не повторяются в каждой строке телеметрии, а определяются через внешние ключи.

### в) Осознанная денормализация

Для быстрого чтения и машинного обучения можно использовать широкое представление `host_state_18`: одна строка на узел и момент времени с 18 параметрами. Оно строится из нормализованной телеметрии; отсутствующим измерениям соответствуют NULL.

Обычный VIEW вычисляет результат при чтении. Материализованное представление обновляется по расписанию через `REFRESH MATERIALIZED VIEW`; для CONCURRENTLY нужен подходящий уникальный индекс. При большом объёме данных можно пересчитывать только изменившиеся интервалы с учётом поздних измерений. Исторические значения связываются с метаданными, действовавшими в момент измерения.

## 3. Пороги во времени

Спроектируйте хранение **порогов срабатывания** (warning / alarm) для датчиков так, чтобы можно было ответить:
«какой порог действовал для TE-302 12 марта 2025?» и «кто и когда его изменил?».

Напишите DDL с ограничением на непересечение интервалов (`exclude using gist`; понадобится `create extension if not exists btree_gist`) и запрос на первый вопрос.

Решение:

### Модель и DDL

Для упражнения используется отдельная схема `exercise03`. На один датчик и уровень severity одновременно действует не более одного порога. Используются полуоткрытые интервалы `[from, to)`: соседние версии могут соприкасаться границами. В примере считаем срабатыванием `value >= threshold_value`; направление и единица закреплены за датчиком. Связь warning < alarm между уровнями потребовала бы отдельной межстрочной проверки, здесь её не предполагаем.

Журнал `threshold_audit` сохраняет старую и новую строки при вставке/изменении, время, роль БД и ответственного инженера. Это различает время действия порога и время его редактирования. `changed_by` связывается с пользователем приложения; журнал защищается от изменения и удаления. Удаление версий запрещено триггером: прекращение действия оформляется закрытием интервала.

```sql
create extension if not exists btree_gist with schema public;
create schema exercise03;
set search_path = exercise03, public;

create table sensor (
    id int generated always as identity primary key,
    tag text not null unique,
    unit_of_measure text not null
);
create table engineer (
    id int generated always as identity primary key,
    tab_no text not null unique,
    full_name text not null
);
create table threshold_version (
    id bigint generated always as identity primary key,
    sensor_id int not null references sensor(id) on delete restrict,
    severity text not null check (severity in ('warning', 'alarm')),
    threshold_value numeric not null,
    valid_period tstzrange not null,
    changed_by int not null references engineer(id) on delete restrict,
    changed_at timestamptz not null default clock_timestamp(),
    check (not isempty(valid_period)
           and not lower_inf(valid_period)
           and isfinite(lower(valid_period))
           and lower_inc(valid_period) and not upper_inc(valid_period)),
    exclude using gist (
        sensor_id with =, severity with =, valid_period with &&
    )
);
create table threshold_audit (
    id bigint generated always as identity primary key,
    threshold_id bigint not null references threshold_version(id) on delete restrict,
    operation text not null check (operation in ('INSERT', 'UPDATE')),
    engineer_id int not null references engineer(id) on delete restrict,
    db_role text not null,
    recorded_at timestamptz not null default clock_timestamp(),
    before_state jsonb,
    after_state jsonb not null
);

create function stamp_threshold_change() returns trigger
language plpgsql as $$
begin
    if TG_OP = 'DELETE' then
        raise exception 'Версии не удаляются: закройте valid_period';
    end if;
    NEW.changed_at := clock_timestamp();
    return NEW;
end;
$$;
create trigger threshold_stamp before insert or update or delete
on threshold_version for each row execute function stamp_threshold_change();

create function audit_threshold_change() returns trigger
language plpgsql as $$
begin
    insert into threshold_audit
        (threshold_id, operation, engineer_id, db_role, before_state, after_state)
    values (NEW.id, TG_OP, NEW.changed_by, session_user,
            case when TG_OP = 'UPDATE' then to_jsonb(OLD) else null end,
            to_jsonb(NEW));
    return NEW;
end;
$$;
create trigger threshold_audit_write after insert or update
on threshold_version for each row execute function audit_threshold_change();
```

При изменении порога в момент T в **одной транзакции** закрываем прежний интервал на T, указывая `changed_by` инженера, затем вставляем новую версию `[T, infinity)`. Порог прежнего интервала не перезаписывается. EXCLUDE запрещает конкурирующие пересекающиеся версии одного уровня. Аудит также сохраняет исправления ошибочно введённых данных.

### Какой порог действовал 12 марта 2025 года?

Для точного момента (явно выбрана московская зона):

```sql
select s.tag, t.severity, t.threshold_value, s.unit_of_measure, t.valid_period
from exercise03.threshold_version t
join exercise03.sensor s on s.id = t.sensor_id
where s.tag = 'TE-302'
  and t.valid_period @> timestamptz '2025-03-12 12:00:00+03'
order by t.severity;
```

Если в вопросе дана только дата и в течение дня порог менялся, единственного ответа нет. Вернём все версии, действовавшие хотя бы часть этого дня:

```sql
select s.tag, t.severity, t.threshold_value, t.valid_period
from exercise03.threshold_version t
join exercise03.sensor s on s.id = t.sensor_id
where s.tag = 'TE-302'
  and t.valid_period && tstzrange(
      '2025-03-12 00:00:00+03'::timestamptz,
      '2025-03-13 00:00:00+03'::timestamptz, '[)')
order by lower(t.valid_period), t.severity;
```

### Кто и когда изменил?

```sql
select a.recorded_at, a.operation, e.tab_no, e.full_name, a.db_role,
       a.before_state, a.after_state
from exercise03.threshold_audit a
join exercise03.engineer e on e.id = a.engineer_id
join exercise03.threshold_version t on t.id = a.threshold_id
join exercise03.sensor s on s.id = t.sensor_id
where s.tag = 'TE-302'
order by a.recorded_at, a.id;
```

Период действия отвечает «что действовало в момент X» по текущей версии истории; аудит отвечает «кто, когда и что исправлял». Если нужен вопрос «что система считала действующим на X по состоянию знаний на Y», потребуется бивременная модель (valid time + system time) либо восстановление состояния по журналу; одного `changed_at` для этого недостаточно.
