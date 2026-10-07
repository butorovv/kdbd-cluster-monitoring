-- =====================================================================
--  Семинар 3 — аналитический практикум. Ваши решения.
--  ФИО: ______________________   Группа: ________
--
--  Перед началом:        make setup SEM=03   (новые таблицы component, sensor_mount, flow_link, unit_spec)
--  Прогнать весь файл:   make run SEM=03
-- =====================================================================
SET TIMEZONE = 'Europe/Moscow';   -- без этого время будет в UTC и не совпадёт с ожидаемым


-- =====================================================================
--  Блок A · Соединения
-- =====================================================================

-- Задача 1. Площадки: число агрегатов и датчиков
-- Ожидается: 3 строки: Восточная 2 / 4, Северная 4 / 13, Южная 1 / 1
-- Задача 1
select st.name as station,
       count(distinct u.id) as unit_count,
       count(s.id) as sensor_count
from public.station st
left join public.unit u on u.station_id = st.id
left join public.sensor s on s.unit_id = u.id
group by st.id, st.name
order by st.name;


-- Задача 2. Серьёзные события (warning, alarm, unplanned_stop) по каждому агрегату, с нулями
-- Ожидается: 7 строк: K-2 — 5, P-2 — 3, K-1 и K-4 — 0
-- Задача 2
select u.id as unit_id, count(e.id) as serious_events
from public.unit u
left join public.event e
  on e.unit_id = u.id
 and lower(trim(e.severity)) in ('warning', 'alarm', 'unplanned_stop')
group by u.id
order by u.id;


-- Задача 3. Листья дерева component: сначала NOT IN, затем NOT EXISTS. Почему по-разному?
-- Ожидается: NOT IN — 0; NOT EXISTS — 40
-- Задача 3
select c.id, c.name, c.kind
from public.component c
where c.id not in (select parent_id from public.component)
order by c.id;

-- В parent_id есть NULL у корней. NOT IN даёт UNKNOWN для остальных
-- кандидатов, поэтому ни одна строка не проходит WHERE.
select c.id, c.name, c.kind
from public.component c
where not exists (
    select 1 from public.component child where child.parent_id = c.id
)
order by c.id;


-- Задача 4. Последнее серьёзное событие каждого агрегата (агрегаты без событий — тоже)
-- Ожидается: 7 строк; у K-2 — unplanned_stop 02.09 14:20; у K-1 и K-4 пусто
-- Задача 4
select u.id as unit_id, last_event.ts, last_event.severity, last_event.message
from public.unit u
left join lateral (
    select e.ts, lower(trim(e.severity)) as severity, e.message
    from public.event e
    where e.unit_id = u.id
      and lower(trim(e.severity)) in ('warning', 'alarm', 'unplanned_stop')
    order by e.ts desc, e.id desc
    limit 1
) last_event on true
order by u.id;


-- =====================================================================
--  Блок B · Группировка
-- =====================================================================

-- Задача 5. Сводная таблица: события каждого уровня по агрегатам (K-4 — с нулями)
-- Ожидается: 7 строк; K-2: 3 / 2 / 2 / 1, всего 8
-- Задача 5
select u.id as unit_id,
       count(e.id) filter (where lower(trim(e.severity)) = 'info') as info,
       count(e.id) filter (where lower(trim(e.severity)) = 'warning') as warning,
       count(e.id) filter (where lower(trim(e.severity)) = 'alarm') as alarm,
       count(e.id) filter (where lower(trim(e.severity)) = 'unplanned_stop') as unplanned_stop,
       count(e.id) as total
from public.unit u
left join public.event e on e.unit_id = u.id
group by u.id
order by u.id;


-- Задача 6. Число измерений по площадке и виду датчика + подытоги + общий итог
-- Ожидается: 11 строк; Северная — 17257; ВСЕГО — 24462
-- Задача 6
select coalesce(st.name, 'ВСЕГО') as station,
       coalesce(s.kind, 'ИТОГО') as sensor_kind,
       count(*) as reading_count
from public.station st
join public.unit u on u.station_id = st.id
join public.sensor s on s.unit_id = u.id
join public.telemetry t on t.sensor_id = s.id
group by grouping sets ((st.name, s.kind), (st.name), ())
order by grouping(st.name), st.name, grouping(s.kind), s.kind;


-- Задача 7. Датчики температуры: среднее, медиана, 95-й процентиль, ст. отклонение
-- Ожидается: 4 строки; TE-302: 66.1 / 71.2 / 83.8 / 12.8
-- Задача 7
-- Статистики рассчитываются для датчиков с измерениями; у TE-999 данных нет.
select s.tag,
       round(avg(t.value), 1) as mean,
       round((percentile_cont(0.5) within group (order by t.value))::numeric, 1) as median,
       round((percentile_cont(0.95) within group (order by t.value))::numeric, 1) as p95,
       round(stddev(t.value), 1) as stddev
from public.sensor s
join public.telemetry t on t.sensor_id = s.id
where s.kind = 'temp'
group by s.id, s.tag
order by stddev(t.value) desc, s.tag;
-- TE-302 выделяется большим разбросом температуры и ростом перед остановкой K-2.


-- =====================================================================
--  Блок C · Подзапросы, WITH, календарь
-- =====================================================================

-- Задача 8. VT-103: пропущенные минуты 2 сентября (начало, конец, число)
-- Ожидается: 02:00 — 02:34, 35 минут
-- Задача 8
with calendar as (
    select generate_series(
        '2026-09-02 00:00+03'::timestamptz,
        '2026-09-03 00:00+03'::timestamptz - interval '1 minute',
        interval '1 minute'
    ) as ts
), missing as (
    select c.ts
    from calendar c
    left join public.telemetry t
      on t.ts = c.ts
     and t.sensor_id = (select id from public.sensor where tag = 'VT-103')
    where t.sensor_id is null
), islands as (
    select ts, ts - row_number() over (order by ts) * interval '1 minute' as gap_id
    from missing
)
select min(ts) as gap_start, max(ts) as gap_end, count(*) as missing_minutes
from islands
group by gap_id
order by gap_start;


-- Задача 9. Почасовая таблица: TE-301, TE-302, TE-303 в столбцах
-- Ожидается: 25 строк; в 13:00: 66.5 / 83.8 / 66.4
-- Задача 9
with hourly as (
    select date_trunc('hour', t.ts) as hour, s.tag, avg(t.value) as mean_value
    from public.telemetry t
    join public.sensor s on s.id = t.sensor_id
    where s.tag in ('TE-301', 'TE-302', 'TE-303')
    group by date_trunc('hour', t.ts), s.tag
)
select hour,
       round(avg(mean_value) filter (where tag = 'TE-301'), 1) as te_301,
       round(avg(mean_value) filter (where tag = 'TE-302'), 1) as te_302,
       round(avg(mean_value) filter (where tag = 'TE-303'), 1) as te_303
from hourly
group by hour
order by hour;


-- =====================================================================
--  Блок D · Оконные функции
-- =====================================================================

-- Задача 10. Последняя запись о работах для каждого агрегата
-- Ожидается: 7 строк; у K-2 — 02.09 19:00
-- Задача 10
with ranked as (
    select m.*, row_number() over (
        partition by m.unit_id order by m.performed_at desc, m.id desc
    ) as rn
    from public.maintenance m
)
select u.id as unit_id, m.performed_at, m.work_type, m.notes
from public.unit u
left join ranked m on m.unit_id = u.id and m.rn = 1
order by u.id;


-- Задача 11. Время с предыдущего события на том же агрегате; пять самых коротких
-- Ожидается: минимум 2 минуты, дважды у P-2
-- Задача 11
with previous_events as (
    select e.id, e.unit_id, e.ts, lower(trim(e.severity)) as severity,
           lag(e.ts) over (partition by e.unit_id order by e.ts, e.id) as previous_ts
    from public.event e
)
select unit_id, ts, severity, previous_ts, ts - previous_ts as elapsed
from previous_events
where previous_ts is not null
order by elapsed, unit_id, ts, id
limit 5;


-- Задача 12. Скользящее среднее TE-302 за 15 минут: когда впервые > 80 сырые и сглаженные
-- Ожидается: сырые — 12:45; скользящее — 12:52
-- Задача 12
with rolling as (
    select t.ts, t.value,
           avg(t.value) over (
               order by t.ts
               range between interval '14 minutes' preceding and current row
           ) as mean_15_minutes
    from public.telemetry t
    join public.sensor s on s.id = t.sensor_id
    where s.tag = 'TE-302'
)
select min(ts) filter (where value > 80) as first_raw_above_80,
       min(ts) filter (where mean_15_minutes > 80) as first_mean_above_80
from rolling;


-- Задача 13. Серьёзные события Северной за 2 сентября с накопленным итогом
-- Ожидается: 6 строк; итог от 1 до 6
-- Задача 13
select e.unit_id, e.ts, lower(trim(e.severity)) as severity, e.message,
       count(*) over (
           order by e.ts, e.id rows between unbounded preceding and current row
       ) as running_total
from public.event e
join public.unit u on u.id = e.unit_id
join public.station st on st.id = u.station_id
where st.name = 'Северная'
  and e.ts >= '2026-09-02 00:00+03'::timestamptz
  and e.ts < '2026-09-03 00:00+03'::timestamptz
  and lower(trim(e.severity)) in ('warning', 'alarm', 'unplanned_stop')
order by e.ts, e.id;


-- =====================================================================
--  Блок E · Рекурсивные запросы
-- =====================================================================

-- Задача 14. Дерево состава K-2 с отступами
-- Ожидается: 13 строк, глубина 0–3
-- Задача 14
with recursive tree as (
    select c.id, c.parent_id, c.name, c.kind, 0 as depth, array[c.id] as path
    from public.component c
    where c.unit_id = 'K-2' and c.parent_id is null
    union all
    select child.id, child.parent_id, child.name, child.kind,
           tree.depth + 1, tree.path || child.id
    from tree
    join public.component child on child.parent_id = tree.id
    where child.id <> all(tree.path)
)
select id, repeat('  ', depth) || name as component_name, kind, depth
from tree
order by path;


-- Задача 15. Агрегат каждого датчика по дереву (вверх от sensor_mount) и сравнение с sensor.unit_id
-- Ожидается: 18 строк, все true
-- Задача 15
with recursive up as (
    select sm.sensor_id, c.id, c.parent_id, c.unit_id, array[c.id] as path
    from public.sensor_mount sm
    join public.component c on c.id = sm.component_id
    union all
    select up.sensor_id, p.id, p.parent_id, p.unit_id, up.path || p.id
    from up
    join public.component p on p.id = up.parent_id
    where p.id <> all(up.path)
)
select s.tag, s.unit_id as declared_unit, up.unit_id as tree_unit,
       s.unit_id = up.unit_id as matches
from up
join public.sensor s on s.id = up.sensor_id
where up.parent_id is null
order by s.tag;


-- Задача 16. Для каждого агрегата: глубина дерева, число деталей и узлов
-- Ожидается: компрессоры 3 / 8 / 4; насосы 2 / 3 / 2; COOL-1 2 / 2 / 1
-- Задача 16
with recursive tree as (
    select c.unit_id, c.id, c.kind, 0 as depth, array[c.id] as path
    from public.component c
    where c.parent_id is null
    union all
    select tree.unit_id, child.id, child.kind, tree.depth + 1, tree.path || child.id
    from tree
    join public.component child on child.parent_id = tree.id
    where child.id <> all(tree.path)
)
select unit_id, max(depth) as max_depth,
       count(*) filter (where kind = 'part') as part_count,
       count(*) filter (where kind = 'assembly') as assembly_count
from tree
group by unit_id
order by unit_id;


-- =====================================================================
--  Блок F · jsonb
-- =====================================================================

-- Задача 17. Характеристики из unit_spec; агрегаты с подшипниками 6312
-- Ожидается: порога нет у K-4, P-1, P-2; 6312 — K-1, K-2
-- Задача 17
select unit_id,
       specs ->> 'manufacturer' as manufacturer,
       (specs ->> 'power_kw')::numeric as power_kw,
       jsonb_array_length(coalesce(specs -> 'bearings', '[]'::jsonb)) as bearing_count,
       coalesce(specs #>> '{limits,temp,warning}', 'нет') as temp_warning
from public.unit_spec
order by unit_id;

select unit_id
from public.unit_spec
where specs @> '{"bearings": [{"type": "6312"}]}'::jsonb
order by unit_id;


-- =====================================================================
--  Со звёздочкой (на балл не влияют)
-- =====================================================================

-- Задача 18*. Интервалы, когда TE-302 непрерывно выше 80 °C
-- Ожидается: 12:45–12:51 (7 мин) и 12:53–15:09 (137 мин)
-- Задача 18*



-- Задача 19*. Что зависит от P-1 по flow_link (в графе цикл!)
-- Ожидается: K-1, K-2 — 1 шаг; COOL-1 — 2
-- Задача 19*



-- Задача 20*. Первое превышение порога warning из unit_spec, минут выше, доля суток
-- Ожидается: K-2: 12:45, 144 мин, 10 %; COOL-1: 13:18, 463 мин, 32 %
-- Задача 20*


