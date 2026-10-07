-- =====================================================================
--  Семинар 3 · дополнительные таблицы учебного датасета
--  Загрузить (можно повторно, таблицы пересоздаются):   make setup SEM=03
--  Основные таблицы семинара 1 (unit, sensor, telemetry, event, maintenance) не меняются.
-- =====================================================================
set timezone = 'Europe/Moscow';
set client_min_messages = warning;

drop table if exists sensor_mount, component, flow_link, unit_spec cascade;

-- ---------- Состав агрегата: дерево узлов и деталей ----------
-- Корень дерева — сам агрегат. Код агрегата (unit_id) записан ТОЛЬКО в корне:
-- для любой детали его нужно найти, поднявшись по дереву (задача 12).
create table component (
    id         int  primary key,
    parent_id  int  references component(id),
    unit_id    text references unit(id),
    name       text not null,
    kind       text not null check (kind in ('unit', 'assembly', 'part')),
    check ((parent_id is null) = (unit_id is not null))   -- код агрегата есть только у корня
);
comment on table component is 'Состав агрегата: узлы (assembly) и детали (part); дерево по parent_id';

insert into component (id, parent_id, unit_id, name, kind) values
  (1, NULL, 'K-1', 'Агрегат K-1', 'unit'),
  (2, 1, NULL, 'Компрессорная часть', 'assembly'),
  (3, 2, NULL, 'Ротор', 'assembly'),
  (4, 3, NULL, 'Подшипник опорный №3', 'part'),
  (5, 3, NULL, 'Подшипник опорный №4', 'part'),
  (6, 3, NULL, 'Рабочее колесо', 'part'),
  (7, 2, NULL, 'Корпус', 'part'),
  (8, 1, NULL, 'Привод', 'assembly'),
  (9, 8, NULL, 'Двигатель', 'part'),
  (10, 8, NULL, 'Муфта', 'part'),
  (11, 1, NULL, 'Система смазки', 'assembly'),
  (12, 11, NULL, 'Маслонасос', 'part'),
  (13, 11, NULL, 'Фильтр масляный', 'part'),
  (14, NULL, 'K-2', 'Агрегат K-2', 'unit'),
  (15, 14, NULL, 'Компрессорная часть', 'assembly'),
  (16, 15, NULL, 'Ротор', 'assembly'),
  (17, 16, NULL, 'Подшипник опорный №3', 'part'),
  (18, 16, NULL, 'Подшипник опорный №4', 'part'),
  (19, 16, NULL, 'Рабочее колесо', 'part'),
  (20, 15, NULL, 'Корпус', 'part'),
  (21, 14, NULL, 'Привод', 'assembly'),
  (22, 21, NULL, 'Двигатель', 'part'),
  (23, 21, NULL, 'Муфта', 'part'),
  (24, 14, NULL, 'Система смазки', 'assembly'),
  (25, 24, NULL, 'Маслонасос', 'part'),
  (26, 24, NULL, 'Фильтр масляный', 'part'),
  (27, NULL, 'K-3', 'Агрегат K-3', 'unit'),
  (28, 27, NULL, 'Компрессорная часть', 'assembly'),
  (29, 28, NULL, 'Ротор', 'assembly'),
  (30, 29, NULL, 'Подшипник опорный №3', 'part'),
  (31, 29, NULL, 'Подшипник опорный №4', 'part'),
  (32, 29, NULL, 'Рабочее колесо', 'part'),
  (33, 28, NULL, 'Корпус', 'part'),
  (34, 27, NULL, 'Привод', 'assembly'),
  (35, 34, NULL, 'Двигатель', 'part'),
  (36, 34, NULL, 'Муфта', 'part'),
  (37, 27, NULL, 'Система смазки', 'assembly'),
  (38, 37, NULL, 'Маслонасос', 'part'),
  (39, 37, NULL, 'Фильтр масляный', 'part'),
  (40, NULL, 'K-4', 'Агрегат K-4', 'unit'),
  (41, 40, NULL, 'Компрессорная часть', 'assembly'),
  (42, 41, NULL, 'Ротор', 'assembly'),
  (43, 42, NULL, 'Подшипник опорный №3', 'part'),
  (44, 42, NULL, 'Подшипник опорный №4', 'part'),
  (45, 42, NULL, 'Рабочее колесо', 'part'),
  (46, 41, NULL, 'Корпус', 'part'),
  (47, 40, NULL, 'Привод', 'assembly'),
  (48, 47, NULL, 'Двигатель', 'part'),
  (49, 47, NULL, 'Муфта', 'part'),
  (50, 40, NULL, 'Система смазки', 'assembly'),
  (51, 50, NULL, 'Маслонасос', 'part'),
  (52, 50, NULL, 'Фильтр масляный', 'part'),
  (53, NULL, 'P-1', 'Агрегат P-1', 'unit'),
  (54, 53, NULL, 'Насосная часть', 'assembly'),
  (55, 54, NULL, 'Рабочее колесо', 'part'),
  (56, 54, NULL, 'Уплотнение вала', 'part'),
  (57, 53, NULL, 'Привод', 'assembly'),
  (58, 57, NULL, 'Двигатель', 'part'),
  (59, NULL, 'P-2', 'Агрегат P-2', 'unit'),
  (60, 59, NULL, 'Насосная часть', 'assembly'),
  (61, 60, NULL, 'Рабочее колесо', 'part'),
  (62, 60, NULL, 'Уплотнение вала', 'part'),
  (63, 59, NULL, 'Привод', 'assembly'),
  (64, 63, NULL, 'Двигатель', 'part'),
  (65, NULL, 'COOL-1', 'Агрегат COOL-1', 'unit'),
  (66, 65, NULL, 'Теплообменные секции', 'part'),
  (67, 65, NULL, 'Вентилятор', 'assembly'),
  (68, 67, NULL, 'Двигатель вентилятора', 'part');

-- ---------- Где установлен датчик ----------
create table sensor_mount (
    sensor_id     int primary key references sensor(id),
    component_id  int not null references component(id)
);
comment on table sensor_mount is 'На каком узле или детали установлен датчик';

insert into sensor_mount (sensor_id, component_id)
select s.id, m.component_id
from (values
  ('TE-301', 4),
  ('VT-101', 4),
  ('PT-201', 7),
  ('LD-001', 9),
  ('TE-999', 5),
  ('TE-302', 17),
  ('VT-102', 17),
  ('PT-202', 20),
  ('LD-002', 22),
  ('TE-303', 30),
  ('VT-103', 30),
  ('PT-203', 33),
  ('LD-003', 35),
  ('PT-211', 54),
  ('LD-011', 58),
  ('PT-212', 60),
  ('LD-012', 64),
  ('TE-331', 66)
) as m(tag, component_id)
join sensor s on s.tag = m.tag;

-- ---------- Технологические связи между агрегатами ----------
-- Контур охлаждения: насос подаёт охлаждающую жидкость в компрессоры, нагретая жидкость
-- идёт в воздушный охладитель, охлаждённая возвращается к насосу. В графе есть ЦИКЛ.
create table flow_link (
    from_unit  text not null references unit(id),
    to_unit    text not null references unit(id),
    medium     text not null,
    primary key (from_unit, to_unit)
);
comment on table flow_link is 'Подача: выход агрегата from_unit идёт на вход агрегата to_unit';

insert into flow_link (from_unit, to_unit, medium) values
  ('P-1',    'K-1',    'охлаждающая жидкость'),
  ('P-1',    'K-2',    'охлаждающая жидкость'),
  ('P-2',    'K-3',    'охлаждающая жидкость'),
  ('P-2',    'K-4',    'охлаждающая жидкость'),
  ('K-1',    'COOL-1', 'нагретая жидкость'),
  ('K-2',    'COOL-1', 'нагретая жидкость'),
  ('COOL-1', 'P-1',    'охлаждённая жидкость');

-- ---------- Технические характеристики (слабоструктурированные данные) ----------
-- У разных типов агрегатов разный набор характеристик — поэтому jsonb.
-- Обратите внимание: у K-4 (в резерве) порогов нет.
create table unit_spec (
    unit_id  text  primary key references unit(id),
    specs    jsonb not null
);
comment on table unit_spec is 'Технические характеристики агрегата; limits — пороги срабатывания по видам датчиков';

insert into unit_spec (unit_id, specs) values
  ('K-1', '{"manufacturer": "Завод А", "power_kw": 16000, "rpm": 5300,
            "bearings": [{"no": 3, "type": "6312"}, {"no": 4, "type": "6312"}],
            "limits": {"temp": {"warning": 80, "alarm": 85}, "vibration": {"warning": 3.0, "alarm": 3.8}}}'),
  ('K-2', '{"manufacturer": "Завод А", "power_kw": 16000, "rpm": 5300,
            "bearings": [{"no": 3, "type": "6312"}, {"no": 4, "type": "6312"}],
            "limits": {"temp": {"warning": 80, "alarm": 85}, "vibration": {"warning": 3.0, "alarm": 3.8}}}'),
  ('K-3', '{"manufacturer": "Завод Б", "power_kw": 16000, "rpm": 5600,
            "bearings": [{"no": 3, "type": "6314"}, {"no": 4, "type": "6314"}],
            "limits": {"temp": {"warning": 82, "alarm": 88}, "vibration": {"warning": 3.2, "alarm": 4.0}}}'),
  ('K-4', '{"manufacturer": "Завод Б", "power_kw": 16000, "rpm": 5600,
            "bearings": [{"no": 3, "type": "6314"}, {"no": 4, "type": "6314"}]}'),
  ('P-1', '{"manufacturer": "Завод В", "power_kw": 1900, "flow_m3h": 180,
            "limits": {"pressure": {"min": 1.0}}}'),
  ('P-2', '{"manufacturer": "Завод В", "power_kw": 1900, "flow_m3h": 180,
            "limits": {"pressure": {"min": 1.0}}}'),
  ('COOL-1', '{"manufacturer": "Завод Г", "sections": 4, "fans": 2,
            "limits": {"temp": {"warning": 37, "alarm": 40}}}');

create index on unit_spec using gin (specs);
analyze component, sensor_mount, flow_link, unit_spec;
