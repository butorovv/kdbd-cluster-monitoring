-- Семинар 4. Обязательные SQL-решения задач 2 и 8.
-- Запуск после сброса: make setup SEM=04 && make run SEM=04.
-- Повторный запуск файла также требует сброса (миграция удаляет severity).
-- Опыты с намеренными ошибками и порядок двух сессий: lab_journal.md.
\set ON_ERROR_STOP on
SET TIME ZONE 'Europe/Moscow';

-- =====================================================================
-- Задача 2. Вся миграция, включая DDL, фиксируется одной транзакцией.
-- =====================================================================
BEGIN;

CREATE TABLE public.lab_severity (
    id integer PRIMARY KEY,
    code text NOT NULL UNIQUE,
    rank integer NOT NULL UNIQUE CHECK (rank BETWEEN 1 AND 4)
);
INSERT INTO public.lab_severity (id, code, rank) VALUES
    (1, 'info', 1),
    (2, 'warning', 2),
    (3, 'alarm', 3),
    (4, 'unplanned_stop', 4);

ALTER TABLE public.lab_event ADD COLUMN severity_id integer
    REFERENCES public.lab_severity(id);
UPDATE public.lab_event AS e
SET severity_id = s.id
FROM public.lab_severity AS s
WHERE s.code = lower(trim(e.severity));
-- Если встретится неизвестный уровень, NOT NULL прервёт транзакцию;
-- исходные строки и столбец severity сохранятся после ROLLBACK.
ALTER TABLE public.lab_event ALTER COLUMN severity_id SET NOT NULL;
ALTER TABLE public.lab_event DROP COLUMN severity;

COMMIT;

SELECT s.code, count(*) AS event_count
FROM public.lab_event AS e
JOIN public.lab_severity AS s ON s.id = e.severity_id
GROUP BY s.id, s.code, s.rank
ORDER BY s.rank;

-- =====================================================================
-- Задача 8. Исправленное перемещение: единый порядок блокировки строк.
-- При make run блоки A и B исполняются последовательно: это проверка SQL.
-- Для конкурентного опыта после сброса копируйте блоки в разные сессии:
--   1. A: BEGIN и SELECT ... FOR UPDATE.
--   2. B: BEGIN и SELECT ... FOR UPDATE (ждёт).
--   3. A: оба UPDATE и COMMIT.
--   4. B: после завершения SELECT оба UPDATE и COMMIT.
-- Между A и B данные НЕ сбрасывать. Начальные остатки: Северная 10,
-- Восточная 4; после обеих встречных передач снова 10 и 4.
-- =====================================================================

-- Сессия A: Северная -> Восточная, 1 шт.
BEGIN;
SELECT station, part_code, qty
FROM public.lab_stock
WHERE part_code = '6312'
ORDER BY station
FOR UPDATE;

UPDATE public.lab_stock SET qty = qty - 1
WHERE station = 'Северная' AND part_code = '6312';
UPDATE public.lab_stock SET qty = qty + 1
WHERE station = 'Восточная' AND part_code = '6312';
COMMIT;

-- Сессия B: Восточная -> Северная, 1 шт.
BEGIN;
SELECT station, part_code, qty
FROM public.lab_stock
WHERE part_code = '6312'
ORDER BY station
FOR UPDATE;

UPDATE public.lab_stock SET qty = qty - 1
WHERE station = 'Восточная' AND part_code = '6312';
UPDATE public.lab_stock SET qty = qty + 1
WHERE station = 'Северная' AND part_code = '6312';
COMMIT;

SELECT station, part_code, qty FROM public.lab_stock ORDER BY station;
