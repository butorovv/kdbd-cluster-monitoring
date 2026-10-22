# Семинар 4. Лаборатория транзакций

Проверено 22.10.2026 на PostgreSQL 17.11, база `plant`, пользователь `student`,
часовой пояс `Europe/Moscow`. A и B — два независимых соединения `psql`.
Ниже приведён фактический вывод сервера, а не переписанные ожидаемые ответы.
Команды и ответы расположены в порядке выполнения; для ожидавшего запроса
ответ показан после освобождения блокировки. Коды ошибок получены из
переменной `psql` `:SQLSTATE`; служебные маркеры завершения команд опущены.
Пауза при проверке ожидания составляла не менее 0,25 с без ответа сервера;
затем блокирующая транзакция продолжалась в другой сессии.

## Как запустить и повторить

Из корня репозитория при работающем Docker:

```sh
make up
make setup SEM=04
make psql  # терминал A
make psql  # терминал B, отдельное окно
```

В A:

```sql
\set PROMPT1 '[A] %/%R%x%# '
\pset pager off
SET TIME ZONE 'Europe/Moscow';
\timing on
```

В B — те же настройки, но `[B]` в `PROMPT1`.
`*` в приглашении означает открытую транзакцию, `!` — прерванную ошибкой.
В интерактивных опытах с намеренными ошибками оставьте `ON_ERROR_STOP` выключенным.

Перед **каждым вариантом опыта** выполните `ROLLBACK;` в обеих сессиях,
затем `make setup SEM=04` в командной оболочке. Не сбрасывайте данные между
шагами одного опыта или между A и B: это разрушит проверяемое взаимодействие.
После ошибки при необходимости выполните `ROLLBACK;`; исключение — опыт 1
с восстановлением к `SAVEPOINT`. Предупреждение `there is no transaction in
progress` при `ROLLBACK` вне транзакции безвредно.

`setup.sql` пересоздаёт только лабораторные таблицы и копирует `public.event`.
В нём нет триггера, обеспечивающего межстрочное правило задачи 7: нарушение
этого правила нужно воспроизвести. Исходные учебные таблицы и `project` не меняются.
Названия шести работ в очереди демонстрационные; условия задач зависят от
их идентификаторов, состояния и количества.

Готовые SQL-решения задач 2 и 8 находятся в [seminar04.sql](seminar04.sql):

```sh
make setup SEM=04
make run SEM=04
```

Этот запуск проверяет исправленную миграцию и последовательно выполняет две
встречные передачи. Для конкурентного опыта 8 используйте блоки A/B из файла
и порядок, указанный в его комментариях и в журнале ниже. Остальные опыты
воспроизводятся командами из соответствующего протокола, переключаясь между
терминалами по меткам A/B. Строки таблиц, `BEGIN`, `UPDATE 1`, сообщения ошибок
и прочие ответы сервера в блоках `text` вводить не нужно.

## Задача 1. Одна ошибка — откат всей транзакции

- **Уровень изоляции:** Read Committed; работает только A.
- **Что увидели:** списание 5 при наличии 4 нарушило `lab_stock_qty_check`
  (`23514`); следующий запрос получил `25P02`. На `COMMIT` сервер ответил
  `ROLLBACK`, на Северной осталось 10.
- **Причина:** без точки сохранения ошибка переводит всю транзакцию в
  прерванное состояние; частичное списание 2 не фиксируется. В приглашении
  после ошибки был символ `!` — `[A] plant=!#`.
- **Исправление:** после первого списания создать `SAVEPOINT before_east`,
  после ошибки выполнить `ROLLBACK TO SAVEPOINT before_east`, списать на
  Восточной 4 и зафиксировать. Итог: Северная 8, Восточная 0; первое списание
  сохранено, неудачная часть отменена. См. [транзакции и точки сохранения PostgreSQL](https://www.postgresql.org/docs/17/tutorial-transactions.html).

Фрагмент отдельной интерактивной проверки приглашения:

```text
[A] plant=*# ERROR:  new row for relation "lab_stock" violates check constraint "lab_stock_qty_check"
DETAIL:  Failing row contains (Восточная, 6312, -1, 1).
[A] plant=!#
```


### Полный откат

```text
-- A, команда 1
BEGIN;
BEGIN
-- A, команда 2
UPDATE lab_stock SET qty = qty - 2 WHERE station = 'Северная' AND part_code = '6312';
UPDATE 1
-- A, команда 3
UPDATE lab_stock SET qty = qty - 5 WHERE station = 'Восточная' AND part_code = '6312';
ERROR:  new row for relation "lab_stock" violates check constraint "lab_stock_qty_check"
DETAIL:  Failing row contains (Восточная, 6312, -1, 1).
-- SQLSTATE: 23514
-- A, команда 4
SELECT qty FROM lab_stock WHERE station = 'Северная' AND part_code = '6312';
ERROR:  current transaction is aborted, commands ignored until end of transaction block
-- SQLSTATE: 25P02
-- A, команда 5
COMMIT;
ROLLBACK
-- A, команда 6
SELECT qty FROM lab_stock WHERE station = 'Северная' AND part_code = '6312';
 qty
-----
  10
(1 row)
```


### Повтор с точкой сохранения

```text
-- A, команда 1
BEGIN;
BEGIN
-- A, команда 2
UPDATE lab_stock SET qty = qty - 2 WHERE station = 'Северная' AND part_code = '6312';
UPDATE 1
-- A, команда 3
SAVEPOINT before_east;
SAVEPOINT
-- A, команда 4
UPDATE lab_stock SET qty = qty - 5 WHERE station = 'Восточная' AND part_code = '6312';
ERROR:  new row for relation "lab_stock" violates check constraint "lab_stock_qty_check"
DETAIL:  Failing row contains (Восточная, 6312, -1, 1).
-- SQLSTATE: 23514
-- A, команда 5
ROLLBACK TO SAVEPOINT before_east;
ROLLBACK
-- A, команда 6
UPDATE lab_stock SET qty = qty - 4 WHERE station = 'Восточная' AND part_code = '6312';
UPDATE 1
-- A, команда 7
COMMIT;
COMMIT
-- A, команда 8
SELECT station, qty, version FROM lab_stock ORDER BY station;
  station  | qty | version
-----------+-----+---------
 Восточная |   0 |       1
 Северная  |   8 |       1
(2 rows)
-- A, команда 9
SELECT qty FROM lab_stock WHERE station = 'Северная' AND part_code = '6312';
 qty
-----
   8
(1 row)
-- A, команда 10
SELECT qty FROM lab_stock WHERE station = 'Восточная' AND part_code = '6312';
 qty
-----
   0
(1 row)
```


## Задача 2. Миграция severity в справочник

- **Уровень изоляции:** Read Committed, одна транзакция A для всей миграции.
- **Что увидели:** первое сопоставление обновило 24 строки. Не сопоставились
  событие `id=10`, P-1, `03:14`, значение `'warning '` с пробелом, и `id=11`,
  P-2, `05:12`, значение `'Alarm'` с заглавной буквой. Установка `NOT NULL`
  получила `23502`, `COMMIT` ответил `ROLLBACK`.
- **Причина:** точное сравнение с `code` учитывает пробелы и регистр.
  В PostgreSQL этот `CREATE TABLE` и последующие `ALTER TABLE` входят в
  транзакцию: после отката справочника нет, старый `severity` есть,
  нового `severity_id` нет. DDL и DML отменились вместе.
- **Исправление:** сопоставить по `lower(trim(e.severity))`. Получено
  `UPDATE 26`, затем успешный `COMMIT`: info 15, warning 5, alarm 4,
  unplanned_stop 2. `severity_id` имеет внешний ключ и `NOT NULL`, старый
  `severity` удалён; `code` и `rank` справочника уникальны.

Сравнение с другими СУБД относится к обычным постоянным таблицам.
В MySQL 8.4 `CREATE TABLE`/`ALTER TABLE` вызывают неявный commit;
пользовательский `ROLLBACK` не отменяет такой `CREATE TABLE`.
«Атомарный DDL» MySQL не делает DDL частью общей пользовательской транзакции.
Источник: [MySQL: Statements That Cause an Implicit Commit](https://dev.mysql.com/doc/refman/8.4/en/implicit-commit.html).
В Oracle неявный commit выполняется **до синтаксически корректного DDL**, даже
если он затем завершится ошибкой, и **после успешного DDL**. Поэтому целиком
откатить такую цепочку DDL/DML одним `ROLLBACK` не получится.
Источник: [Oracle: COMMIT](https://docs.oracle.com/en/database/oracle/oracle-database/21/sqlrf/COMMIT.html).


### Неудачная попытка и проверка отката DDL

```text
-- A, команда 1
BEGIN;
BEGIN
-- A, команда 2
CREATE TABLE lab_severity (id integer PRIMARY KEY, code text NOT NULL UNIQUE, rank integer NOT NULL UNIQUE CHECK (rank BETWEEN 1 AND 4));
CREATE TABLE
-- A, команда 3
INSERT INTO lab_severity VALUES (1, 'info', 1), (2, 'warning', 2), (3, 'alarm', 3), (4, 'unplanned_stop', 4);
INSERT 0 4
-- A, команда 4
ALTER TABLE lab_event ADD COLUMN severity_id integer REFERENCES lab_severity(id);
ALTER TABLE
-- A, команда 5
UPDATE lab_event e SET severity_id = s.id FROM lab_severity s WHERE s.code = e.severity;
UPDATE 24
-- A, команда 6
SELECT id, unit_id, ts, '[' || severity || ']' AS original_severity FROM lab_event WHERE severity_id IS NULL ORDER BY id;
 id | unit_id |           ts           | original_severity
----+---------+------------------------+-------------------
 10 | P-1     | 2026-09-02 03:14:00+03 | [warning ]
 11 | P-2     | 2026-09-02 05:12:00+03 | [Alarm]
(2 rows)
-- A, команда 7
ALTER TABLE lab_event ALTER COLUMN severity_id SET NOT NULL;
ERROR:  column "severity_id" of relation "lab_event" contains null values
-- SQLSTATE: 23502
-- A, команда 8
COMMIT;
ROLLBACK
-- A, команда 9
\dt public.lab_*
             List of relations
 Schema |      Name      | Type  |  Owner
--------+----------------+-------+---------
 public | lab_event      | table | student
 public | lab_job        | table | student
 public | lab_stock      | table | student
 public | lab_unit_state | table | student
(4 rows)
-- A, команда 10
SELECT to_regclass('public.lab_severity') IS NULL AS dictionary_rolled_back;
 dictionary_rolled_back
------------------------
 t
(1 row)
-- A, команда 11
SELECT count(*) FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'lab_event' AND column_name = 'severity';
 count
-------
     1
(1 row)
-- A, команда 12
SELECT count(*) FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'lab_event' AND column_name = 'severity_id';
 count
-------
     0
(1 row)
```


### Исправленная миграция из seminar04.sql

```text
-- A, команда 1
BEGIN;
BEGIN
-- A, команда 2
CREATE TABLE public.lab_severity (
    id integer PRIMARY KEY,
    code text NOT NULL UNIQUE,
    rank integer NOT NULL UNIQUE CHECK (rank BETWEEN 1 AND 4)
);
CREATE TABLE
-- A, команда 3
INSERT INTO public.lab_severity (id, code, rank) VALUES
    (1, 'info', 1),
    (2, 'warning', 2),
    (3, 'alarm', 3),
    (4, 'unplanned_stop', 4);
INSERT 0 4
-- A, команда 4
ALTER TABLE public.lab_event ADD COLUMN severity_id integer
    REFERENCES public.lab_severity(id);
ALTER TABLE
-- A, команда 5
UPDATE public.lab_event AS e
SET severity_id = s.id
FROM public.lab_severity AS s
WHERE s.code = lower(trim(e.severity));
UPDATE 26
-- A, команда 6
-- исходные строки и столбец severity сохранятся после ROLLBACK.
ALTER TABLE public.lab_event ALTER COLUMN severity_id SET NOT NULL;
ALTER TABLE
-- A, команда 7
ALTER TABLE public.lab_event DROP COLUMN severity;
ALTER TABLE
-- A, команда 8
COMMIT;
COMMIT
-- A, команда 9
SELECT s.code, count(*) AS event_count
FROM public.lab_event AS e
JOIN public.lab_severity AS s ON s.id = e.severity_id
GROUP BY s.id, s.code, s.rank
ORDER BY s.rank;
      code      | event_count
----------------+-------------
 info           |          15
 warning        |           5
 alarm          |           4
 unplanned_stop |           2
(4 rows)
-- A, команда 10
SELECT count(*) FROM lab_event WHERE severity_id IS NOT NULL;
 count
-------
    26
(1 row)
-- A, команда 11
SELECT count(*) FROM lab_severity;
 count
-------
     4
(1 row)
-- A, команда 12
SELECT count(*) FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'lab_event' AND column_name = 'severity';
 count
-------
     0
(1 row)
```


## Задача 3. Потерянное обновление

- **Уровень изоляции:** Read Committed в A и B.
- **Что увидели:** обе сессии прочитали 10, обе успешно записали 8,
  итог — 8 вместо 6, ошибок не было.
- **Причина:** приложение вычислило новую величину из устаревшего чтения.
  Блокировка строки во время `UPDATE` не проверяет, что константа 8 была
  рассчитана по актуальному остатку. Списание B потерялось при его
  `UPDATE ... SET qty = 8`: он сохранил то же значение после commit A.
- **Исправление:** вычислять `qty - 2` внутри `UPDATE`, блокировать строку
  перед чтением либо обнаруживать конфликт и повторять всю операцию
  (варианты проверены в задаче 4 и задаче 10).


### Два успешных списания с неверным итогом

```text
-- A, команда 1
BEGIN;
BEGIN
-- B, команда 2
BEGIN;
BEGIN
-- A, команда 3
SELECT qty FROM lab_stock WHERE station = 'Северная' AND part_code = '6312';
 qty
-----
  10
(1 row)
-- B, команда 4
SELECT qty FROM lab_stock WHERE station = 'Северная' AND part_code = '6312';
 qty
-----
  10
(1 row)
-- A, команда 5
UPDATE lab_stock SET qty = 8 WHERE station = 'Северная' AND part_code = '6312';
UPDATE 1
-- A, команда 6
COMMIT;
COMMIT
-- B, команда 7
UPDATE lab_stock SET qty = 8 WHERE station = 'Северная' AND part_code = '6312';
UPDATE 1
-- B, команда 8
COMMIT;
COMMIT
-- A, команда 9
SELECT qty FROM lab_stock WHERE station = 'Северная' AND part_code = '6312';
 qty
-----
   8
(1 row)
```


## Задача 4. Три исправления потерянного обновления

- **Уровни изоляции:** 4а и 4б — Read Committed; 4в — Repeatable Read.
- **Что увидели:** атомарное списание и `FOR UPDATE` дали итог 6.
  В дополнительном опыте 4а A списал 8, B после ожидания получил `UPDATE 0`,
  остаток 2. В 4в B получил `40001`, после полного повтора итог 6.
- **Причина:** в 4а B ждёт блокировку той же строки. После commit A PostgreSQL
  применяет выражение к обновлённой версии: `8 - 2`, а не `10 - 2`.
  Условие `qty >= 3` также проверяется повторно: после списания A осталось 2,
  строка больше не подходит и не обновляется. Это штатный `UPDATE 0`,
  без нарушения `CHECK`. См. [Read Committed: ожидание и повторная проверка WHERE](https://www.postgresql.org/docs/17/transaction-iso.html#XACT-READ-COMMITTED).
- **Почему исправления работают:** 4а объединяет чтение и изменение в одной
  команде; 4б удерживает блокировку от чтения до commit, поэтому B читает
  уже 8 и вычисляет 6. Второй способ нужен, когда решение требует нескольких
  шагов и связанных проверок, которые неудобно выразить одним `UPDATE`.
  В 4в снимок B устарел, а конфликт записи обнаруживается как `40001`;
  новый запуск начинает новое чтение и заново вычисляет остаток.

При `40001` недостаточно повторить последний `UPDATE` с прежней константой:
старый снимок и расчёт уже не подходят. Нужны `ROLLBACK`, новый `BEGIN`,
повтор всех чтений и проверок, новый расчёт, затем запись и commit.
Источник: [PostgreSQL: Serialization Failure Handling](https://www.postgresql.org/docs/17/mvcc-serialization-failure-handling.html).


### 4а. Вычитание внутри UPDATE

```text
-- A, команда 1
BEGIN;
BEGIN
-- B, команда 2
BEGIN;
BEGIN
-- A, команда 3
UPDATE lab_stock SET qty = qty - 2 WHERE station = 'Северная' AND part_code = '6312';
UPDATE 1
-- B, команда 4
UPDATE lab_stock SET qty = qty - 2 WHERE station = 'Северная' AND part_code = '6312';
-- Запрос не завершился; продолжение в другой сессии.
-- A, команда 5
COMMIT;
COMMIT
-- Ответ: B, команда 4
UPDATE 1
-- B, команда 6
COMMIT;
COMMIT
-- A, команда 7
SELECT qty FROM lab_stock WHERE station = 'Северная' AND part_code = '6312';
 qty
-----
   6
(1 row)
```


### 4а. Дополнительный опыт: недостаточный остаток

```text
-- A, команда 1
BEGIN;
BEGIN
-- B, команда 2
BEGIN;
BEGIN
-- A, команда 3
UPDATE lab_stock SET qty = qty - 8 WHERE station = 'Северная' AND part_code = '6312';
UPDATE 1
-- B, команда 4
UPDATE lab_stock SET qty = qty - 3 WHERE station = 'Северная' AND part_code = '6312' AND qty >= 3;
-- Запрос не завершился; продолжение в другой сессии.
-- A, команда 5
COMMIT;
COMMIT
-- Ответ: B, команда 4
UPDATE 0
-- B, команда 6
COMMIT;
COMMIT
-- A, команда 7
SELECT qty FROM lab_stock WHERE station = 'Северная' AND part_code = '6312';
 qty
-----
   2
(1 row)
```


### 4б. Блокировка перед чтением

```text
-- A, команда 1
BEGIN;
BEGIN
-- B, команда 2
BEGIN;
BEGIN
-- A, команда 3
SELECT qty FROM lab_stock WHERE station = 'Северная' AND part_code = '6312' FOR UPDATE;
 qty
-----
  10
(1 row)
-- B, команда 4
SELECT qty FROM lab_stock WHERE station = 'Северная' AND part_code = '6312' FOR UPDATE;
-- Запрос не завершился; продолжение в другой сессии.
-- A, команда 5
UPDATE lab_stock SET qty = 8 WHERE station = 'Северная' AND part_code = '6312';
UPDATE 1
-- A, команда 6
COMMIT;
COMMIT
-- Ответ: B, команда 4
 qty
-----
   8
(1 row)
-- B, команда 7
UPDATE lab_stock SET qty = 6 WHERE station = 'Северная' AND part_code = '6312';
UPDATE 1
-- B, команда 8
COMMIT;
COMMIT
-- A, команда 9
SELECT qty FROM lab_stock WHERE station = 'Северная' AND part_code = '6312';
 qty
-----
   6
(1 row)
```


### 4в. Конфликт и повтор всей транзакции

```text
-- A, команда 1
BEGIN ISOLATION LEVEL REPEATABLE READ;
BEGIN
-- B, команда 2
BEGIN ISOLATION LEVEL REPEATABLE READ;
BEGIN
-- A, команда 3
SELECT qty FROM lab_stock WHERE station = 'Северная' AND part_code = '6312';
 qty
-----
  10
(1 row)
-- B, команда 4
SELECT qty FROM lab_stock WHERE station = 'Северная' AND part_code = '6312';
 qty
-----
  10
(1 row)
-- A, команда 5
UPDATE lab_stock SET qty = 8 WHERE station = 'Северная' AND part_code = '6312';
UPDATE 1
-- A, команда 6
COMMIT;
COMMIT
-- B, команда 7
UPDATE lab_stock SET qty = 8 WHERE station = 'Северная' AND part_code = '6312';
ERROR:  could not serialize access due to concurrent update
-- SQLSTATE: 40001
-- B, команда 8
ROLLBACK;
ROLLBACK
-- B, команда 9
BEGIN ISOLATION LEVEL REPEATABLE READ;
BEGIN
-- B, команда 10
SELECT qty FROM lab_stock WHERE station = 'Северная' AND part_code = '6312';
 qty
-----
   8
(1 row)
-- B, команда 11
UPDATE lab_stock SET qty = 6 WHERE station = 'Северная' AND part_code = '6312';
UPDATE 1
-- B, команда 12
COMMIT;
COMMIT
-- A, команда 13
SELECT qty FROM lab_stock WHERE station = 'Северная' AND part_code = '6312';
 qty
-----
   6
(1 row)
```


## Задача 5. Неповторяемое чтение

- **Уровни изоляции:** A — сначала Read Committed, после сброса Repeatable
  Read; B — Read Committed, autocommit, без `BEGIN`.
- **Что увидели:** Read Committed — 10, затем 7; Repeatable Read — 10 и 10.
- **Причина:** Read Committed получает снимок в начале каждого оператора;
  второй `SELECT` видит уже зафиксированное изменение B. Repeatable Read
  использует один снимок с первого запроса/изменения данных транзакции,
  а не с самого `BEGIN`.
- **Исправление:** отчёт из нескольких запросов выполнять в одной транзакции
  Repeatable Read, при необходимости `READ ONLY`. Его части будут согласованы
  по одному снимку. Источник: [PostgreSQL: SET TRANSACTION](https://www.postgresql.org/docs/17/sql-set-transaction.html).


### Read Committed

```text
-- A, команда 1
BEGIN ISOLATION LEVEL READ COMMITTED;
BEGIN
-- A, команда 2
SELECT qty FROM lab_stock WHERE station = 'Северная' AND part_code = '6312';
 qty
-----
  10
(1 row)
-- B, команда 3
UPDATE lab_stock SET qty = 7 WHERE station = 'Северная' AND part_code = '6312';
UPDATE 1
-- A, команда 4
SELECT qty FROM lab_stock WHERE station = 'Северная' AND part_code = '6312';
 qty
-----
   7
(1 row)
-- A, команда 5
COMMIT;
COMMIT
```


### Repeatable Read

```text
-- A, команда 1
BEGIN ISOLATION LEVEL REPEATABLE READ;
BEGIN
-- A, команда 2
SELECT qty FROM lab_stock WHERE station = 'Северная' AND part_code = '6312';
 qty
-----
  10
(1 row)
-- B, команда 3
UPDATE lab_stock SET qty = 7 WHERE station = 'Северная' AND part_code = '6312';
UPDATE 1
-- A, команда 4
SELECT qty FROM lab_stock WHERE station = 'Северная' AND part_code = '6312';
 qty
-----
  10
(1 row)
-- A, команда 5
COMMIT;
COMMIT
```


## Задача 6. Фантомное чтение

- **Уровни изоляции:** A — Read Committed, затем Repeatable Read после сброса;
  вставка B — autocommit.
- **Что увидели:** Read Committed — 6, затем 7 новых заявок;
  Repeatable Read — 6 и 6.
- **Причина:** новый снимок Read Committed включает вставленную B заявку 7.
  На Repeatable Read снимок A остаётся прежним, новая строка в него не попадает.
- **Исправление:** для стабильного набора строк в PostgreSQL использовать
  Repeatable Read. Стандарт SQL допускает фантомы на этом уровне,
  но PostgreSQL даёт более сильную гарантию и не допускает их.
  Источник: [PostgreSQL: таблица 13.1 уровней изоляции](https://www.postgresql.org/docs/17/transaction-iso.html).


### Read Committed

```text
-- A, команда 1
BEGIN ISOLATION LEVEL READ COMMITTED;
BEGIN
-- A, команда 2
SELECT count(*) FROM lab_job WHERE status = 'new';
 count
-------
     6
(1 row)
-- B, команда 3
INSERT INTO lab_job (id, unit_id, task) VALUES (7, 'K-2', 'Проверить муфту');
INSERT 0 1
-- A, команда 4
SELECT count(*) FROM lab_job WHERE status = 'new';
 count
-------
     7
(1 row)
-- A, команда 5
COMMIT;
COMMIT
```


### Repeatable Read

```text
-- A, команда 1
BEGIN ISOLATION LEVEL REPEATABLE READ;
BEGIN
-- A, команда 2
SELECT count(*) FROM lab_job WHERE status = 'new';
 count
-------
     6
(1 row)
-- B, команда 3
INSERT INTO lab_job (id, unit_id, task) VALUES (7, 'K-2', 'Проверить муфту');
INSERT 0 1
-- A, команда 4
SELECT count(*) FROM lab_job WHERE status = 'new';
 count
-------
     6
(1 row)
-- A, команда 5
COMMIT;
COMMIT
```


## Задача 7. Аномалия сериализации

- **Уровни изоляции:** сначала Repeatable Read в обеих сессиях, после сброса
  Serializable в обеих.
- **Что увидели:** при Repeatable Read оба увидели 2 работающих компрессора
  и вывели разные агрегаты в резерв, оба commit успешны: в работе 0.
  При Serializable commit B получил `40001`; K-3 остался `in_service`.
- **Причина:** это write skew: каждая транзакция меняет свою строку, опираясь
  на общий снимок. Автоматические блокировки изменяемых строк не конфликтуют,
  а Repeatable Read не защищает такое межстрочное правило.
- **Исправление:** Serializable обнаруживает несовместимые зависимости
  чтения/записи. После `40001` приложение повторяет всю транзакцию и проверку
  правила: теперь работающий агрегат только один, выводить K-3 в резерв нельзя.
  Этот повтор выполнен ниже без `UPDATE`. Источник: [PostgreSQL: согласованность на уровне приложения](https://www.postgresql.org/docs/17/applevel-consistency.html).

Блокировки строк могут помочь при другом протоколе: обе транзакции должны
заранее блокировать весь набор, определяющий правило, в общем порядке, либо
общую строку площадки. Просто блокировать собственный выводимый компрессор,
как при обычных `UPDATE` в этом опыте, недостаточно.


### Repeatable Read: правило нарушено

```text
-- A, команда 1
BEGIN ISOLATION LEVEL REPEATABLE READ;
BEGIN
-- B, команда 2
BEGIN ISOLATION LEVEL REPEATABLE READ;
BEGIN
-- A, команда 3
SELECT count(*) FROM lab_unit_state WHERE station = 'Северная' AND status = 'in_service';
 count
-------
     2
(1 row)
-- B, команда 4
SELECT count(*) FROM lab_unit_state WHERE station = 'Северная' AND status = 'in_service';
 count
-------
     2
(1 row)
-- A, команда 5
UPDATE lab_unit_state SET status = 'reserve' WHERE unit_id = 'K-1';
UPDATE 1
-- B, команда 6
UPDATE lab_unit_state SET status = 'reserve' WHERE unit_id = 'K-3';
UPDATE 1
-- A, команда 7
COMMIT;
COMMIT
-- B, команда 8
COMMIT;
COMMIT
-- A, команда 9
SELECT unit_id, status FROM lab_unit_state ORDER BY unit_id;
 unit_id | status
---------+---------
 K-1     | reserve
 K-2     | repair
 K-3     | reserve
 K-4     | reserve
(4 rows)
-- A, команда 10
SELECT count(*) FROM lab_unit_state WHERE station = 'Северная' AND status = 'in_service';
 count
-------
     0
(1 row)
```


### Serializable: конфликт обнаружен

```text
-- A, команда 1
BEGIN ISOLATION LEVEL SERIALIZABLE;
BEGIN
-- B, команда 2
BEGIN ISOLATION LEVEL SERIALIZABLE;
BEGIN
-- A, команда 3
SELECT count(*) FROM lab_unit_state WHERE station = 'Северная' AND status = 'in_service';
 count
-------
     2
(1 row)
-- B, команда 4
SELECT count(*) FROM lab_unit_state WHERE station = 'Северная' AND status = 'in_service';
 count
-------
     2
(1 row)
-- A, команда 5
UPDATE lab_unit_state SET status = 'reserve' WHERE unit_id = 'K-1';
UPDATE 1
-- B, команда 6
UPDATE lab_unit_state SET status = 'reserve' WHERE unit_id = 'K-3';
UPDATE 1
-- A, команда 7
COMMIT;
COMMIT
-- B, команда 8
COMMIT;
ERROR:  could not serialize access due to read/write dependencies among transactions
DETAIL:  Reason code: Canceled on identification as a pivot, during commit attempt.
HINT:  The transaction might succeed if retried.
-- SQLSTATE: 40001
-- A, команда 9
SELECT unit_id, status FROM lab_unit_state ORDER BY unit_id;
 unit_id |   status
---------+------------
 K-1     | reserve
 K-2     | repair
 K-3     | in_service
 K-4     | reserve
(4 rows)
-- A, команда 10
SELECT count(*) FROM lab_unit_state WHERE station = 'Северная' AND status = 'in_service';
 count
-------
     1
(1 row)
```


### Повтор с новой проверкой бизнес-правила

```text
-- B, команда 1
ROLLBACK;
WARNING:  there is no transaction in progress
ROLLBACK
-- B, команда 2
BEGIN ISOLATION LEVEL SERIALIZABLE;
BEGIN
-- B, команда 3
SELECT count(*) FROM lab_unit_state WHERE station = 'Северная' AND status = 'in_service';
 count
-------
     1
(1 row)
-- B, команда 4
COMMIT;
COMMIT
```


## Задача 8. Взаимоблокировка и единый порядок захвата

- **Уровень изоляции:** Read Committed в A и B.
- **Что увидели:** в данном запуске жертвой стала **сессия A**,
  получившая `40P01`. Её `COMMIT` ответил `ROLLBACK`; другая транзакция
  завершилась. После сброса и исправления обе передачи завершились,
  конечные остатки: Северная 10, Восточная 4, сумма 14.
- **Причина:** A удерживает Северную и ждёт Восточную; B удерживает Восточную
  и ждёт Северную. Получается цикл A → B → A. В первом опыте прошла только
  передача B: Северная 11, Восточная 3.
- **Исправление:** в обеих сессиях перед изменениями заблокировать обе строки
  через `SELECT ... ORDER BY station FOR UPDATE`. В нашем окружении порядок —
  Восточная, Северная. B ждёт на первом захвате, пока A завершит всю передачу;
  цикла нет. SQL обеих передач находится в [seminar04.sql](seminar04.sql).

Выбор жертвы не гарантирован: при повторении это может быть другая сессия.
Приложение после `40P01` отменяет неудачную транзакцию и при необходимости
повторяет её целиком. См. [PostgreSQL: взаимоблокировки и порядок захвата](https://www.postgresql.org/docs/17/explicit-locking.html#LOCKING-DEADLOCKS).


### Разный порядок захвата: deadlock

```text
-- A, команда 1
BEGIN;
BEGIN
-- B, команда 2
BEGIN;
BEGIN
-- A, команда 3
UPDATE lab_stock SET qty = qty - 1 WHERE station = 'Северная' AND part_code = '6312';
UPDATE 1
-- B, команда 4
UPDATE lab_stock SET qty = qty - 1 WHERE station = 'Восточная' AND part_code = '6312';
UPDATE 1
-- A, команда 5
UPDATE lab_stock SET qty = qty + 1 WHERE station = 'Восточная' AND part_code = '6312';
-- Запрос не завершился; продолжение в другой сессии.
-- B, команда 6
UPDATE lab_stock SET qty = qty + 1 WHERE station = 'Северная' AND part_code = '6312';
-- Ответ: A, команда 5
ERROR:  deadlock detected
DETAIL:  Process 1493 waits for ShareLock on transaction 933; blocked by process 1500.
Process 1500 waits for ShareLock on transaction 932; blocked by process 1493.
HINT:  See server log for query details.
CONTEXT:  while updating tuple (0,2) in relation "lab_stock"
-- SQLSTATE: 40P01
-- Ответ: B, команда 6
UPDATE 1
-- A, команда 7
COMMIT;
ROLLBACK
-- B, команда 8
COMMIT;
COMMIT
-- A, команда 9
SELECT station, qty, version FROM lab_stock ORDER BY station;
  station  | qty | version
-----------+-----+---------
 Восточная |   3 |       1
 Северная  |  11 |       1
(2 rows)
-- A, команда 10
SELECT sum(qty) FROM lab_stock;
 sum
-----
  14
(1 row)
```


### Одинаковый порядок захвата: обе передачи успешны

```text
-- A, команда 1
BEGIN;
BEGIN
-- B, команда 2
BEGIN;
BEGIN
-- A, команда 3
SELECT station, part_code, qty FROM lab_stock WHERE part_code = '6312' ORDER BY station FOR UPDATE;
  station  | part_code | qty
-----------+-----------+-----
 Восточная | 6312      |   4
 Северная  | 6312      |  10
(2 rows)
-- B, команда 4
SELECT station, part_code, qty FROM lab_stock WHERE part_code = '6312' ORDER BY station FOR UPDATE;
-- Запрос не завершился; продолжение в другой сессии.
-- A, команда 5
UPDATE lab_stock SET qty = qty - 1 WHERE station = 'Северная' AND part_code = '6312';
UPDATE 1
-- A, команда 6
UPDATE lab_stock SET qty = qty + 1 WHERE station = 'Восточная' AND part_code = '6312';
UPDATE 1
-- A, команда 7
COMMIT;
COMMIT
-- Ответ: B, команда 4
  station  | part_code | qty
-----------+-----------+-----
 Восточная | 6312      |   5
 Северная  | 6312      |   9
(2 rows)
-- B, команда 8
UPDATE lab_stock SET qty = qty - 1 WHERE station = 'Восточная' AND part_code = '6312';
UPDATE 1
-- B, команда 9
UPDATE lab_stock SET qty = qty + 1 WHERE station = 'Северная' AND part_code = '6312';
UPDATE 1
-- B, команда 10
COMMIT;
COMMIT
-- A, команда 11
SELECT station, qty, version FROM lab_stock ORDER BY station;
  station  | qty | version
-----------+-----+---------
 Восточная |   4 |       1
 Северная  |  10 |       1
(2 rows)
-- A, команда 12
SELECT qty FROM lab_stock WHERE station = 'Северная' AND part_code = '6312';
 qty
-----
  10
(1 row)
-- A, команда 13
SELECT qty FROM lab_stock WHERE station = 'Восточная' AND part_code = '6312';
 qty
-----
   4
(1 row)
```


## Задача 9. Очередь: FOR UPDATE и SKIP LOCKED

- **Уровень изоляции:** Read Committed, выбор и обновление A в одной транзакции.
- **Что увидели:** A получил заявку 1. С обычным `FOR UPDATE` B ждал commit A,
  затем получил заявку 2. С `SKIP LOCKED` B получил заявку 2 сразу, пока A
  ещё удерживал заявку 1. После контрольного `ROLLBACK` A заявка 1 снова доступна.
- **Причина:** обычный блокирующий SELECT ждёт первую подходящую строку;
  после ожидания заявка 1 уже `in_progress` и не удовлетворяет `status='new'`.
  `SKIP LOCKED` пропускает заблокированную строку и продолжает выбор.
- **Исправление:** исполнители выбирают доступную заявку через `FOR UPDATE
  SKIP LOCKED` и в той же транзакции записывают статус, исполнителя и время.
  Если A упадёт до commit, после обнаружения разрыва соединения его транзакция
  откатится и блокировки снимутся: заявка снова доступна. `ORDER BY id` задаёт
  стабильный порядок выбора; при пропуске занятых строк это не строгая FIFO.
  Источник: [PostgreSQL: SELECT, locking clause](https://www.postgresql.org/docs/17/sql-select.html#SQL-FOR-UPDATE-SHARE).

В исходном сценарии B выполняет только `SELECT` и `COMMIT`, поэтому заявка 2
после опыта остаётся `new`: выбор под блокировкой сам по себе не означает
сохранённое назначение исполнителя. Результат ниже это подтверждает.


### Обычный FOR UPDATE: B ждёт

```text
-- A, команда 1
BEGIN;
BEGIN
-- B, команда 2
BEGIN;
BEGIN
-- A, команда 3
SELECT id, task FROM lab_job WHERE status = 'new' ORDER BY id LIMIT 1 FOR UPDATE;
 id |        task
----+---------------------
  1 | Проверить подшипник
(1 row)
-- B, команда 4
SELECT id, task FROM lab_job WHERE status = 'new' ORDER BY id LIMIT 1 FOR UPDATE;
-- Запрос не завершился; продолжение в другой сессии.
-- A, команда 5
UPDATE lab_job SET status = 'in_progress', worker = 'A', taken_at = now() WHERE id = 1;
UPDATE 1
-- A, команда 6
COMMIT;
COMMIT
-- Ответ: B, команда 4
 id |           task
----+--------------------------
  2 | Заменить масляный фильтр
(1 row)
-- B, команда 7
COMMIT;
COMMIT
-- A, команда 8
SELECT id, status, worker FROM lab_job ORDER BY id;
 id |   status    | worker
----+-------------+--------
  1 | in_progress | A
  2 | new         |
  3 | new         |
  4 | new         |
  5 | new         |
  6 | new         |
(6 rows)
```


### SKIP LOCKED: B не ждёт A

```text
-- A, команда 1
BEGIN;
BEGIN
-- B, команда 2
BEGIN;
BEGIN
-- A, команда 3
SELECT id, task FROM lab_job WHERE status = 'new' ORDER BY id LIMIT 1 FOR UPDATE SKIP LOCKED;
 id |        task
----+---------------------
  1 | Проверить подшипник
(1 row)
-- B, команда 4
SELECT id, task FROM lab_job WHERE status = 'new' ORDER BY id LIMIT 1 FOR UPDATE SKIP LOCKED;
 id |           task
----+--------------------------
  2 | Заменить масляный фильтр
(1 row)
-- A, команда 5
UPDATE lab_job SET status = 'in_progress', worker = 'A', taken_at = now() WHERE id = 1;
UPDATE 1
-- A, команда 6
COMMIT;
COMMIT
-- B, команда 7
COMMIT;
COMMIT
-- A, команда 8
SELECT id, status, worker FROM lab_job ORDER BY id;
 id |   status    | worker
----+-------------+--------
  1 | in_progress | A
  2 | new         |
  3 | new         |
  4 | new         |
  5 | new         |
  6 | new         |
(6 rows)
```


### Контроль отката до фиксации назначения

```text
-- A, команда 1
BEGIN;
BEGIN
-- A, команда 2
SELECT id, task FROM lab_job WHERE status = 'new' ORDER BY id LIMIT 1 FOR UPDATE;
 id |        task
----+---------------------
  1 | Проверить подшипник
(1 row)
-- A, команда 3
UPDATE lab_job SET status = 'in_progress', worker = 'A', taken_at = now() WHERE id = 1;
UPDATE 1
-- A, команда 4
ROLLBACK;
ROLLBACK
-- B, команда 5
BEGIN;
BEGIN
-- B, команда 6
SELECT id, task FROM lab_job WHERE status = 'new' ORDER BY id LIMIT 1 FOR UPDATE SKIP LOCKED;
 id |        task
----+---------------------
  1 | Проверить подшипник
(1 row)
-- B, команда 7
ROLLBACK;
ROLLBACK
```


## Задача 10. Оптимистическая блокировка

- **Уровень изоляции:** Read Committed, autocommit в обеих сессиях, без `BEGIN`.
- **Что увидели:** A и B прочитали `(qty, version) = (10, 1)`.
  A получил `UPDATE 1`, B — `UPDATE 0`; состояние стало `(8, 2)`.
  После перечитывания и нового расчёта повтор B получил `UPDATE 1`, итог `(6, 3)`.
- **Причина:** A атомарно изменил остаток и увеличил версию. У B условие
  `version = 1` больше не выполняется, поэтому устаревшее значение не записалось.
  В этом опыте строка существует: `UPDATE 0` указывает на конфликт версии.
- **Исправление:** приложение проверяет число обновлённых строк; при нуле
  перечитывает данные и версию, повторяет проверки и расчёт, затем пробует
  условную запись снова. Оптимистический вариант удобен при редких конфликтах
  и длинном промежутке между чтением и записью: блокировку не удерживают всё
  это время. При частых конфликтах или короткой операции из нескольких шагов
  может быть удобнее `FOR UPDATE`. Сам условный `UPDATE` всё равно использует
  кратковременную блокировку строки.


### Конфликт устаревшей версии

```text
-- A, команда 1
SELECT qty, version FROM lab_stock WHERE station = 'Северная' AND part_code = '6312';
 qty | version
-----+---------
  10 |       1
(1 row)
-- B, команда 2
SELECT qty, version FROM lab_stock WHERE station = 'Северная' AND part_code = '6312';
 qty | version
-----+---------
  10 |       1
(1 row)
-- A, команда 3
UPDATE lab_stock SET qty = 8, version = version + 1 WHERE station = 'Северная' AND part_code = '6312' AND version = 1;
UPDATE 1
-- B, команда 4
UPDATE lab_stock SET qty = 8, version = version + 1 WHERE station = 'Северная' AND part_code = '6312' AND version = 1;
UPDATE 0
-- A, команда 5
SELECT qty, version FROM lab_stock WHERE station = 'Северная' AND part_code = '6312';
 qty | version
-----+---------
   8 |       2
(1 row)
```


### Перечитывание, пересчёт и успешный повтор

```text
-- B, команда 1
SELECT qty, version FROM lab_stock WHERE station = 'Северная' AND part_code = '6312';
 qty | version
-----+---------
   8 |       2
(1 row)
-- B, команда 2
UPDATE lab_stock SET qty = 6, version = version + 1 WHERE station = 'Северная' AND part_code = '6312' AND version = 2;
UPDATE 1
-- B, команда 3
SELECT qty, version FROM lab_stock WHERE station = 'Северная' AND part_code = '6312';
 qty | version
-----+---------
   6 |       3
(1 row)
-- A, команда 4
SELECT qty FROM lab_stock WHERE station = 'Северная' AND part_code = '6312';
 qty
-----
   6
(1 row)
```


## Проверка готовых файлов

- `make setup SEM=04` успешно выполнялся перед каждым вариантом и после
  успешной миграции, возвращая исходный текстовый `severity` и удаляя справочник.
- `make setup SEM=04` + `make run SEM=04` проверены дважды. В SQL-файле включён
  `ON_ERROR_STOP`, ошибок не было; распределение событий 15/5/4/2, всего 26,
  остатки после двух встречных передач 10 и 4.
- Ошибки `23514`, `25P02`, `23502`, `40001`, `40P01` получены только
  в соответствующих намеренно ошибочных опытах. Исправленные варианты успешны.
- После проверки база оставлена в состоянии успешного запуска SQL-файла:
  миграция применена, остатки 10 и 4. Для повторения любого опыта нужен сброс.
- Исходные файлы учебного датасета и семинаров 1–3 не изменены.
  Коммит и отправка в GitHub не выполнялись.
