-- Семинар 4. Сброс только лабораторных таблиц: make setup SEM=04.
-- Перед сбросом завершите транзакции в обеих сессиях (ROLLBACK).
\set ON_ERROR_STOP on
SET TIME ZONE 'Europe/Moscow';
BEGIN;

DROP TABLE IF EXISTS public.lab_event;
DROP TABLE IF EXISTS public.lab_severity;
DROP TABLE IF EXISTS public.lab_job;
DROP TABLE IF EXISTS public.lab_unit_state;
DROP TABLE IF EXISTS public.lab_stock;

CREATE TABLE public.lab_stock (
    station text NOT NULL,
    part_code text NOT NULL,
    qty integer NOT NULL,
    version integer NOT NULL DEFAULT 1 CHECK (version > 0),
    PRIMARY KEY (station, part_code),
    CONSTRAINT lab_stock_qty_check CHECK (qty >= 0)
);
INSERT INTO public.lab_stock (station, part_code, qty) VALUES
    ('Северная', '6312', 10),
    ('Восточная', '6312', 4);

CREATE TABLE public.lab_unit_state (
    unit_id text PRIMARY KEY REFERENCES public.unit(id),
    station text NOT NULL,
    status text NOT NULL CHECK (status IN ('in_service', 'repair', 'reserve'))
);
-- Межстрочное правило «хотя бы один в работе» намеренно не обеспечено
-- ограничением: задача 7 показывает, почему нужна сериализация операций.
INSERT INTO public.lab_unit_state (unit_id, station, status) VALUES
    ('K-1', 'Северная', 'in_service'),
    ('K-2', 'Северная', 'repair'),
    ('K-3', 'Северная', 'in_service'),
    ('K-4', 'Северная', 'reserve');

CREATE TABLE public.lab_job (
    id integer PRIMARY KEY,
    unit_id text NOT NULL REFERENCES public.unit(id),
    task text NOT NULL,
    status text NOT NULL DEFAULT 'new'
        CHECK (status IN ('new', 'in_progress', 'done')),
    worker text,
    taken_at timestamptz
);
INSERT INTO public.lab_job (id, unit_id, task) VALUES
    (1, 'K-1', 'Проверить подшипник'),
    (2, 'K-2', 'Заменить масляный фильтр'),
    (3, 'K-3', 'Проверить вибрацию'),
    (4, 'K-4', 'Осмотреть резервный агрегат'),
    (5, 'P-1', 'Проверить уплотнение'),
    (6, 'P-2', 'Проверить давление');

-- Независимая копия; DEFAULT nextval исходного event не переносится.
CREATE TABLE public.lab_event
    (LIKE public.event INCLUDING CONSTRAINTS INCLUDING INDEXES);
INSERT INTO public.lab_event SELECT * FROM public.event;

COMMIT;
