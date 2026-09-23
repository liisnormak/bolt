-- Kontrollin, mitu erinevat order_try'd ja ticket'it
-- võib olla ühe order_id-ga seotud.

SELECT
    order_id_new,
    COUNT(*) AS rows_count,
    COUNT(DISTINCT order_try_id_new) AS order_try_count,
    COUNT(DISTINCT ticket_id_new) AS ticket_count
FROM takso_andmed_clean
GROUP BY order_id_new
HAVING COUNT(*) > 1
ORDER BY rows_count DESC;

-- Vaatan ühe order'i kõiki ticket'e ja nende overpaid staatust.

SELECT
    order_id_new,
    order_try_id_new,
    ticket_id_new,
    overpaid_ride_ticket
FROM takso_andmed_clean
WHERE order_id_new = 3443
ORDER BY ticket_id_new;

-- Otsin order'id, mille erinevatel ticket'itel on
-- nii overpaid_ride_ticket = 0 kui ka = 1.

SELECT
    order_id_new,
    COUNT(DISTINCT ticket_id_new) AS ticket_count,
    MIN(overpaid_ride_ticket) AS min_overpaid,
    MAX(overpaid_ride_ticket) AS max_overpaid
FROM takso_andmed_clean
GROUP BY order_id_new
HAVING
    MIN(overpaid_ride_ticket) = 0
    AND MAX(overpaid_ride_ticket) = 1
ORDER BY ticket_count DESC;

-- Kontrollin, kas order_id_new ja order_try_id_new
-- erinevad mõnel real.

SELECT
    COUNT(*) AS erinevaid_ridu
FROM takso_andmed_clean
WHERE order_id_new <> order_try_id_new;

-- Kontrollin, kas ühe order_id-ga võib olla seotud
-- mitu erinevat order_try_id väärtust.

SELECT
    order_id_new,
    COUNT(DISTINCT order_try_id_new) AS order_try_count
FROM takso_andmed_clean
GROUP BY order_id_new
HAVING COUNT(DISTINCT order_try_id_new) > 1
ORDER BY order_try_count DESC;

-- Vaatan ühe mitme ticket'iga order'i kõiki andmeid,
-- et näha, millised tunnused muutuvad ticket'ite vahel.

SELECT *
FROM takso_andmed_clean
WHERE order_id_new = 63
ORDER BY ticket_id_new;

SELECT column_name
FROM information_schema.columns
WHERE table_name = 'takso_andmed_clean'
ORDER BY ordinal_position;

-- Kontrollin, kas sama order_id all on sõidu põhiandmed alati samad.
-- Kui päring ei tagasta ridu, saame need turvaliselt order-tasemele viia.

SELECT
    order_id_new
FROM takso_andmed_clean
GROUP BY order_id_new
HAVING
       COUNT(DISTINCT metered_price) > 1
    OR COUNT(DISTINCT upfront_price) > 1
    OR COUNT(DISTINCT distance) > 1
    OR COUNT(DISTINCT duration) > 1
    OR COUNT(DISTINCT predicted_distance) > 1
    OR COUNT(DISTINCT predicted_duration) > 1
    OR COUNT(DISTINCT fraud_score) > 1;

-- Loon kuupäevade dimension-tabeli.
-- Üks kuupäev esineb dimensionis ainult ühe korra.

CREATE TABLE dim_date (
    date_key SERIAL PRIMARY KEY,
    date DATE UNIQUE,
    day_of_week VARCHAR(20),
    day_of_week_nr INTEGER,
    month INTEGER,
    year INTEGER
);

-- Lisan dim_date tabelisse kõik unikaalsed kuupäevad
-- koos nende kuupäevatunnustega.

INSERT INTO dim_date (
    date,
    day_of_week,
    day_of_week_nr,
    month,
    year
)
SELECT DISTINCT
    date,
    day_of_week,
    day_of_week_nr,
    month,
    year
FROM takso_andmed_clean
ORDER BY date;

-- Lisan dim_date tabelisse kõik unikaalsed kuupäevad
-- koos nende kuupäevatunnustega.

INSERT INTO dim_date (
    date,
    day_of_week,
    day_of_week_nr,
    month,
    year
)
SELECT DISTINCT
    date::date,
    day_of_week,
    day_of_week_nr,
    month,
    year
FROM takso_andmed_clean
ORDER BY date::date;

SELECT *
FROM dim_date
ORDER BY date;

-- Loon äpi ja seadme dimension-tabeli.
-- Iga unikaalne rider/driver appi ja seadme kombinatsioon
-- saab oma app_device_key väärtuse.

CREATE TABLE dim_app_device (
    app_device_key SERIAL PRIMARY KEY,
    rider_app_version VARCHAR(50),
    driver_app_version VARCHAR(50),
    driver_device_uid_new INTEGER,
    device_name VARCHAR(100)
);

-- Lisan kõik unikaalsed äpi- ja seadmekombinatsioonid.

INSERT INTO dim_app_device (
    rider_app_version,
    driver_app_version,
    driver_device_uid_new,
    device_name
)
SELECT DISTINCT
    rider_app_version,
    driver_app_version,
    driver_device_uid_new,
    device_name
FROM takso_andmed_clean;

-- Loon äpi ja seadme dimension-tabeli.

CREATE TABLE dim_app_device (
    app_device_key SERIAL PRIMARY KEY,
    rider_app_version VARCHAR(50),
    driver_app_version VARCHAR(50),
    driver_device_uid_new INTEGER,
    device_name VARCHAR(100)
);

-- Kontrollime kas andmed said äpi ja seadme dimension-tabelisse
SELECT COUNT(*)
FROM dim_app_device;

-- Kustutan dim_app_device tabeli ja loon selle puhtalt uuesti.
DROP TABLE dim_app_device;

CREATE TABLE dim_app_device (
    app_device_key SERIAL PRIMARY KEY,
    rider_app_version VARCHAR(50),
    driver_app_version VARCHAR(50),
    driver_device_uid_new INTEGER,
    device_name VARCHAR(100)
);

-- Lisan iga unikaalse app/device kombinatsiooni ainult ühe korra.
INSERT INTO dim_app_device (
    rider_app_version,
    driver_app_version,
    driver_device_uid_new,
    device_name
)
SELECT DISTINCT
    rider_app_version,
    driver_app_version,
    driver_device_uid_new,
    device_name
FROM takso_andmed_clean;

SELECT COUNT(*)
FROM dim_app_device;

-- Loon sõitude fact-tabeli.
-- Üks rida = üks unikaalne order.

CREATE TABLE fact_rides (
    order_id_new INTEGER PRIMARY KEY,
    order_try_id_new INTEGER,

    calc_created VARCHAR(50),
    time VARCHAR(50),

    metered_price REAL,
    upfront_price REAL,
    distance INTEGER,
    duration INTEGER,
    dest_change_number INTEGER,
    predicted_distance REAL,
    predicted_duration REAL,
    fraud_score REAL,

    gps_confidence INTEGER,
    entered_by VARCHAR(50),
    b_state VARCHAR(50),
    prediction_price_type VARCHAR(50),
    change_reason_pricing VARCHAR(50),
    order_state VARCHAR(50),
    order_try_state VARCHAR(50),
    eu_indicator INTEGER,

    is_invalid_ride BOOLEAN,
    fraud_score_status VARCHAR(50),

    date_key INTEGER REFERENCES dim_date(date_key),
    app_device_key INTEGER REFERENCES dim_app_device(app_device_key)
);

-- Täidan fact_rides tabeli.
-- DISTINCT ON tagab, et iga order_id_new kohta jääb ainult üks rida.

INSERT INTO fact_rides (
    order_id_new,
    order_try_id_new,
    calc_created,
    time,
    metered_price,
    upfront_price,
    distance,
    duration,
    dest_change_number,
    predicted_distance,
    predicted_duration,
    fraud_score,
    gps_confidence,
    entered_by,
    b_state,
    prediction_price_type,
    change_reason_pricing,
    order_state,
    order_try_state,
    eu_indicator,
    is_invalid_ride,
    fraud_score_status,
    date_key,
    app_device_key
)
SELECT DISTINCT ON (t.order_id_new)
    t.order_id_new,
    t.order_try_id_new,
    t.calc_created,
    t.time,
    t.metered_price,
    t.upfront_price,
    t.distance,
    t.duration,
    t.dest_change_number,
    t.predicted_distance,
    t.predicted_duration,
    t.fraud_score,
    t.gps_confidence,
    t.entered_by,
    t.b_state,
    t.prediction_price_type,
    t.change_reason_pricing,
    t.order_state,
    t.order_try_state,
    t.eu_indicator,
    t.is_invalid_ride,
    t.fraud_score_status,
    d.date_key,
    a.app_device_key
FROM takso_andmed_clean t

LEFT JOIN dim_date d
    ON t.date::date = d.date

LEFT JOIN dim_app_device a
    ON a.rider_app_version IS NOT DISTINCT FROM t.rider_app_version
    AND a.driver_app_version IS NOT DISTINCT FROM t.driver_app_version
    AND a.driver_device_uid_new IS NOT DISTINCT FROM t.driver_device_uid_new
    AND a.device_name IS NOT DISTINCT FROM t.device_name

ORDER BY t.order_id_new, t.ticket_id_new;

-- Kontrollin, kas fact_rides sisaldab täpselt ühe rea iga order'i kohta.

SELECT
    (SELECT COUNT(DISTINCT order_id_new)
     FROM takso_andmed_clean) AS algsed_orderid,

    (SELECT COUNT(*)
     FROM fact_rides) AS fact_rides_read;

    -- Loon ticket'ite fact-tabeli.
-- Üks rida = üks unikaalne ticket.
-- order_id_new seob ticket'i vastava sõiduga fact_rides tabelis.

CREATE TABLE fact_tickets (
    ticket_id_new INTEGER PRIMARY KEY,
    order_id_new INTEGER NOT NULL REFERENCES fact_rides(order_id_new),
    overpaid_ride_ticket INTEGER
);

-- Lisan kõik ticket'id.
-- Siin ei eemalda me sama order'i kordusi,
-- sest ühel order'il võib olla mitu erinevat ticket'it.

INSERT INTO fact_tickets (
    ticket_id_new,
    order_id_new,
    overpaid_ride_ticket
)
SELECT
    ticket_id_new,
    order_id_new,
    overpaid_ride_ticket
FROM takso_andmed_clean;

-- Kontrollin, et kõik ticket'id jõudsid fact_tickets tabelisse.

SELECT
    (SELECT COUNT(*) FROM takso_andmed_clean) AS algsed_read,
    (SELECT COUNT(*) FROM fact_tickets) AS fact_tickets_read,
    (SELECT COUNT(DISTINCT ticket_id_new) FROM fact_tickets) AS unikaalsed_ticketid;

-- Kontrollin fact_rides tabeli ridade arvu
-- ning order_id ja order_try_id unikaalsust.

SELECT
    COUNT(*) AS rows_total,
    COUNT(DISTINCT order_id_new) AS unique_orders,
    COUNT(DISTINCT order_try_id_new) AS unique_order_tries
FROM fact_rides;

-- Kontrollin, kas sama order_id + order_try_id kombinatsioon
-- esineb fact_rides tabelis rohkem kui ühe korra.

SELECT
    order_id_new,
    order_try_id_new,
    COUNT(*) AS row_count
FROM fact_rides
GROUP BY
    order_id_new,
    order_try_id_new
HAVING COUNT(*) > 1
ORDER BY row_count DESC;

-- Kontrollin, kas ticket_id_new on fact_tickets tabelis unikaalne.

SELECT
    COUNT(*) AS rows_total,
    COUNT(DISTINCT ticket_id_new) AS unique_tickets
FROM fact_tickets;

-- Lisan fact_rides tabelile unikaalse tehnilise võtme,
-- sest order_id_new üksi ei ole unikaalne.

ALTER TABLE fact_rides
ADD COLUMN ride_key SERIAL;

-- Määran ride_key veeru fact_rides tabeli primaarvõtmeks.
-- Primary Key tähendab, et iga ride_key peab olema unikaalne
-- ja selle väärtus ei tohi olla NULL.

ALTER TABLE fact_rides
ADD CONSTRAINT fact_rides_pkey
PRIMARY KEY (ride_key);

-- Kontrollin, milline Primary Key on praegu fact_rides tabelil
-- ja millise veeru/veergudega see seotud on.

SELECT
    conname AS constraint_name,
    pg_get_constraintdef(oid) AS definition
FROM pg_constraint
WHERE conrelid = 'fact_rides'::regclass
  AND contype = 'p';

-- Eemaldan olemasoleva Primary Key constraint'i,
-- sest order_id_new ei ole fact_rides tabelis unikaalne.

ALTER TABLE fact_rides
DROP CONSTRAINT fact_rides_pkey;

-- Eemaldan fact_tickets tabeli vana foreign key seose,
-- sest see viitab fact_rides.order_id_new veerule,
-- mis ei ole tegelikult unikaalne.

ALTER TABLE fact_tickets
DROP CONSTRAINT fact_tickets_order_id_new_fkey;

-- Eemaldan order_id_new peal oleva vana Primary Key constraint'i.

ALTER TABLE fact_rides
DROP CONSTRAINT fact_rides_pkey;

-- Määran iga fact_rides rea unikaalse tehnilise võtme primaarvõtmeks.

ALTER TABLE fact_rides
ADD CONSTRAINT fact_rides_pkey
PRIMARY KEY (ride_key);

-- Sama order + order try kombinatsioon ei tohi fact_rides tabelis korduda.

ALTER TABLE fact_rides
ADD CONSTRAINT fact_rides_order_try_unique
UNIQUE (order_id_new, order_try_id_new);

-- Kontrollin, kui mitme erineva ride/order_try reaga
-- on iga ticketite tabelis olev order_id seotud.

SELECT
    t.order_id_new,
    COUNT(*) AS ride_rows
FROM fact_tickets t
JOIN fact_rides r
    ON t.order_id_new = r.order_id_new
GROUP BY t.order_id_new
HAVING COUNT(*) > 1
ORDER BY ride_rows DESC;

-- Kontrollin, mitme fact_rides reaga saab iga ticket
-- ainult order_id_new kaudu ühenduda.

SELECT
    t.ticket_id_new,
    t.order_id_new,
    COUNT(r.ride_key) AS matching_rides
FROM fact_tickets t
LEFT JOIN fact_rides r
    ON t.order_id_new = r.order_id_new
GROUP BY
    t.ticket_id_new,
    t.order_id_new
HAVING COUNT(r.ride_key) <> 1
ORDER BY matching_rides DESC;

-- Kontrollin, kas fact_tickets sisaldab selliseid order_id väärtusi,
-- mis esinevad fact_rides tabelis rohkem kui ühe korra.

SELECT
    r.order_id_new,
    COUNT(DISTINCT r.ride_key) AS rides,
    COUNT(DISTINCT t.ticket_id_new) AS tickets
FROM fact_rides r
JOIN fact_tickets t
    ON r.order_id_new = t.order_id_new
GROUP BY r.order_id_new
HAVING COUNT(DISTINCT r.ride_key) > 1
ORDER BY rides DESC;

-- Lisan fact_tickets tabelisse ride_key veeru.

ALTER TABLE fact_tickets
ADD COLUMN ride_key INT;

-- Leian igale ticketile vastava fact_rides rea
-- ja salvestan selle ride_key.

UPDATE fact_tickets t
SET ride_key = r.ride_key
FROM fact_rides r
WHERE t.order_id_new = r.order_id_new;

SELECT COUNT(*) AS missing_ride_keys
FROM fact_tickets
WHERE ride_key IS NULL;

ALTER TABLE fact_tickets
ADD CONSTRAINT fact_tickets_ride_key_fkey
FOREIGN KEY (ride_key)
REFERENCES fact_rides(ride_key);

SELECT column_name
FROM information_schema.columns
WHERE table_name = 'fact_rides'
ORDER BY ordinal_position;

SELECT column_name
FROM information_schema.columns
WHERE table_name = 'fact_tickets'
ORDER BY ordinal_position;

SELECT
    conname AS constraint_name,
    contype AS constraint_type,
    pg_get_constraintdef(oid) AS definition
FROM pg_constraint
WHERE conrelid IN (
    'fact_rides'::regclass,
    'fact_tickets'::regclass
)
ORDER BY conrelid::regclass::text, contype;



-- Loon order dimensiooni.
-- Iga order_id_new esineb siin ainult ühe korra.

CREATE TABLE dim_order AS
SELECT DISTINCT order_id_new
FROM fact_rides;

ALTER TABLE dim_order
ADD COLUMN order_key SERIAL PRIMARY KEY;

ALTER TABLE dim_order
ADD CONSTRAINT dim_order_order_id_unique
UNIQUE (order_id_new);

ALTER TABLE fact_rides
ADD COLUMN order_key INT;

ALTER TABLE fact_tickets
ADD COLUMN order_key INT;

UPDATE fact_rides r
SET order_key = d.order_key
FROM dim_order d
WHERE r.order_id_new = d.order_id_new;

UPDATE fact_tickets t
SET order_key = d.order_key
FROM dim_order d
WHERE t.order_id_new = d.order_id_new;

SELECT
    COUNT(*) FILTER (WHERE order_key IS NULL) AS rides_missing_order_key
FROM fact_rides;

SELECT
    COUNT(*) FILTER (WHERE order_key IS NULL) AS tickets_missing_order_key
FROM fact_tickets;

ALTER TABLE fact_rides
ADD CONSTRAINT fact_rides_order_key_fkey
FOREIGN KEY (order_key)
REFERENCES dim_order(order_key);

ALTER TABLE fact_tickets
ADD CONSTRAINT fact_tickets_order_key_fkey
FOREIGN KEY (order_key)
REFERENCES dim_order(order_key);

ALTER TABLE fact_tickets
DROP CONSTRAINT fact_tickets_ride_key_fkey;

ALTER TABLE fact_tickets
DROP COLUMN ride_key;

-- Loon dim_order tabeli.
-- Iga order_id_new esineb siin ainult ühe korra.
-- Dim_order hakkab ühendama fact_rides ja fact_tickets tabeleid orderi tasemel.

CREATE TABLE dim_order AS
SELECT DISTINCT order_id_new
FROM fact_rides;

-- Lisan dim_order tabelisse tehnilise võtme order_key.
-- Sellest saab dim_order tabeli Primary Key.

ALTER TABLE dim_order
ADD COLUMN order_key SERIAL PRIMARY KEY;

-- Määran order_id_new unikaalseks,
-- sest dim_order tabelis peab iga order esinema ainult ühe korra.

ALTER TABLE dim_order
ADD CONSTRAINT dim_order_order_id_unique
UNIQUE (order_id_new);

-- Kontrollin, mitu unikaalset orderit dim_order tabelisse tekkis.
-- Meie varasema kontrolli põhjal peaks tulemus olema 4166.

SELECT COUNT(*) AS orders
FROM dim_order;

-- Kontrollin, kas order_key veerg on juba olemas
-- fact_rides ja fact_tickets tabelites.

SELECT
    table_name,
    column_name
FROM information_schema.columns
WHERE table_name IN ('fact_rides', 'fact_tickets')
  AND column_name = 'order_key';

-- Kontrollin, kas fact_rides tabelis on ridu,
-- millele pole order_key väärtust määratud.
-- Tulemus peab olema 0.

SELECT COUNT(*) AS rides_missing_order_key
FROM fact_rides
WHERE order_key IS NULL;

-- Kontrollin, kas fact_tickets tabelis on ridu,
-- millele pole order_key väärtust määratud.
-- Tulemus peab samuti olema 0.

SELECT COUNT(*) AS tickets_missing_order_key
FROM fact_tickets
WHERE order_key IS NULL;

-- Kontrollin, kas fact_rides ja fact_tickets tabelitel
-- on juba foreign key seosed dim_order tabeliga.

SELECT
    conrelid::regclass AS table_name,
    conname AS constraint_name,
    pg_get_constraintdef(oid) AS definition
FROM pg_constraint
WHERE conrelid IN (
    'fact_rides'::regclass,
    'fact_tickets'::regclass
)
AND contype = 'f'
ORDER BY table_name, constraint_name;

-- Teen tähtskeemi lõppkontrolli.
-- Vaatan iga tabeli ridade arvu ja oluliste võtmete unikaalsust.
-- Ootame:
-- fact_rides = 4943 rida
-- dim_order = 4166 orderit
-- fact_rides ride_key = kõik unikaalsed
-- fact_tickets ticket_id_new = kõik unikaalsed

SELECT
    (SELECT COUNT(*) FROM fact_rides) AS fact_rides_rows,
    (SELECT COUNT(DISTINCT ride_key) FROM fact_rides) AS unique_rides,

    (SELECT COUNT(*) FROM fact_tickets) AS fact_tickets_rows,
    (SELECT COUNT(DISTINCT ticket_id_new) FROM fact_tickets) AS unique_tickets,

    (SELECT COUNT(*) FROM dim_order) AS dim_order_rows,
    (SELECT COUNT(DISTINCT order_id_new) FROM dim_order) AS unique_orders,

    (SELECT COUNT(*) FROM dim_date) AS dim_date_rows,
    (SELECT COUNT(*) FROM dim_app_device) AS dim_app_device_rows;
    
    -- Kontrollin, kas fact_rides tabelis on ordereid,
-- millel on rohkem kui üks order_try_id_new.
-- Kui orderil võib olla mitu try'd, peaks siin ridu leiduma.

SELECT
    order_id_new,
    COUNT(DISTINCT order_try_id_new) AS try_count
FROM fact_rides
GROUP BY order_id_new
HAVING COUNT(DISTINCT order_try_id_new) > 1
ORDER BY try_count DESC;

-- Kontrollin algandmetest, kas ühe order_id_new all
-- võib päriselt olla mitu erinevat order_try_id_new väärtust.
-- See aitab otsustada, milline peab olema fact_rides tabeli grain.

SELECT
    order_id_new,
    COUNT(*) AS rows_in_source,
    COUNT(DISTINCT order_try_id_new) AS different_order_tries,
    COUNT(DISTINCT ticket_id_new) AS different_tickets
FROM takso_andmed_clean
GROUP BY order_id_new
HAVING COUNT(*) > 1
ORDER BY rows_in_source DESC;

-- Kontrollin kogu algandmestikust, kas leidub ordereid,
-- millel on rohkem kui üks erinev order_try_id_new.
-- Kui tulemus on 0, siis order_try ei põhjusta meie andmetes korduvaid ridu.

SELECT COUNT(*) AS orders_with_multiple_tries
FROM (
    SELECT order_id_new
    FROM takso_andmed_clean
    GROUP BY order_id_new
    HAVING COUNT(DISTINCT order_try_id_new) > 1
) x;

-- Teen iga orderi kohta ühe rea.
-- had_overcharge_ticket = 1 tähendab, et selle orderi kohta
-- oli vähemalt üks overcharge'iga seotud CS ticket.
-- Kui sama orderi kohta oli 5 muud ticketit ja 1 overcharge ticket,
-- on tulemus ikkagi 1.

SELECT
    order_key,
    MAX(overpaid_ride_ticket) AS had_overcharge_ticket
FROM fact_tickets
GROUP BY order_key;

-- Loon seadmete dimensioonitabeli.
-- Üks rida kirjeldab ühte unikaalset driver device'i ja device name kombinatsiooni.
-- Seda dimensiooni saame hiljem kasutada näiteks selleks,
-- et uurida GPS confidence'i ja overcharge ticketite seost seadmega.

CREATE TABLE dim_device AS
SELECT DISTINCT
    driver_device_uid_new,
    device_name
FROM dim_app_device;

-- Lisan dim_device tabelile tehnilise primaarvõtme.
-- device_key abil ühendame hiljem dim_device tabeli fact_rides tabeliga.

ALTER TABLE dim_device
ADD COLUMN device_key SERIAL PRIMARY KEY;

-- Kontrollin, mitu rida dim_device tabelisse tekkis
-- ja kas driver_device_uid_new + device_name kombinatsioonid on unikaalsed.

SELECT
    COUNT(*) AS rows_in_dim_device,
    COUNT(DISTINCT (driver_device_uid_new, device_name)) AS unique_devices
FROM dim_device;

-- Loon app-versioonide dimensioonitabeli.
-- Üks rida tähistab unikaalset rider + driver app-versiooni kombinatsiooni.
-- Selle abil saame hiljem uurida, kas teatud app-versioonidega
-- kaasneb näiteks rohkem nõrka GPS-i või overcharge juhtumeid.

CREATE TABLE dim_app_version AS
SELECT DISTINCT
    rider_app_version,
    driver_app_version
FROM dim_app_device;

-- Lisan dim_app_version tabelile tehnilise primaarvõtme.
-- app_version_key abil ühendame hiljem dimensiooni fact_rides tabeliga.

ALTER TABLE dim_app_version
ADD COLUMN app_version_key SERIAL PRIMARY KEY;

-- Kontrollin, et iga rider + driver app-versiooni kombinatsioon
-- esineks dim_app_version tabelis ainult ühe korra.

SELECT
    COUNT(*) AS rows_in_dim_app_version,
    COUNT(DISTINCT (rider_app_version, driver_app_version)) AS unique_app_versions
FROM dim_app_version;

-- Loon hinnastamise konteksti dimensioonitabeli.
-- Üks rida tähistab unikaalset kombinatsiooni:
-- prediction_price_type + change_reason_pricing + entered_by.
-- Seda saame hiljem kasutada, et uurida, kas teatud
-- hinnastamise olukordades esineb rohkem overcharge juhtumeid.

CREATE TABLE dim_pricing_context AS
SELECT DISTINCT
    prediction_price_type,
    change_reason_pricing,
    entered_by
FROM fact_rides;

-- Lisan dim_pricing_context tabelile tehnilise primaarvõtme.
-- pricing_context_key abil ühendame selle hiljem fact_rides tabeliga.

ALTER TABLE dim_pricing_context
ADD COLUMN pricing_context_key SERIAL PRIMARY KEY;

-- Kontrollin, et iga hinnastamise konteksti kombinatsioon
-- esineks dim_pricing_context tabelis ainult ühe korra.

SELECT
    COUNT(*) AS rows_in_dim_pricing_context,
    COUNT(DISTINCT (
        prediction_price_type,
        change_reason_pricing,
        entered_by
    )) AS unique_pricing_contexts
FROM dim_pricing_context;

-- Lisan fact_rides tabelisse device_key veeru.
-- Selle kaudu ühendame iga sõidu õige seadmega dim_device tabelis.

ALTER TABLE fact_rides
ADD COLUMN device_key INT;

-- Täidan fact_rides.device_key väärtused.
-- Praegune app_device_key viib meid vana dim_app_device tabelini,
-- kust saame driver_device_uid_new ja device_name kombinatsiooni.
-- Selle kombinatsiooni järgi leiame uue dim_device.device_key.

UPDATE fact_rides fr
SET device_key = dd.device_key
FROM dim_app_device dad
JOIN dim_device dd
    ON dd.driver_device_uid_new = dad.driver_device_uid_new
    AND dd.device_name IS NOT DISTINCT FROM dad.device_name
WHERE fr.app_device_key = dad.app_device_key;

-- Kontrollin, kas kõik 4166 sõitu said device_key väärtuse.
-- Oodatav tulemus on 0.

SELECT COUNT(*) AS missing_device_key
FROM fact_rides
WHERE device_key IS NULL;

-- Lisan fact_rides tabelisse app_version_key veeru.
-- Selle kaudu ühendame iga sõidu õige rider + driver
-- app-versiooni kombinatsiooniga dim_app_version tabelis.

ALTER TABLE fact_rides
ADD COLUMN app_version_key INT;

-- Täidan fact_rides.app_version_key väärtused.
-- Kasutan vana dim_app_device tabelit, et leida iga sõidu
-- rider_app_version ja driver_app_version.
-- Nende kombinatsiooni järgi leian dim_app_version tabelist õige võtme.

UPDATE fact_rides fr
SET app_version_key = dav.app_version_key
FROM dim_app_device dad
JOIN dim_app_version dav
    ON dav.rider_app_version IS NOT DISTINCT FROM dad.rider_app_version
    AND dav.driver_app_version IS NOT DISTINCT FROM dad.driver_app_version
WHERE fr.app_device_key = dad.app_device_key;

-- Kontrollin, kas kõik 4166 sõitu said app_version_key väärtuse.
-- Oodatav tulemus on 0.

SELECT COUNT(*) AS missing_app_version_key
FROM fact_rides
WHERE app_version_key IS NULL;

-- Lisan fact_rides tabelisse pricing_context_key veeru.
-- Selle kaudu ühendame iga sõidu õige hinnastamise kontekstiga
-- dim_pricing_context tabelis.

ALTER TABLE fact_rides
ADD COLUMN pricing_context_key INT;

-- Täidan fact_rides.pricing_context_key väärtused.
-- Võrdlen kolme hinnastamise konteksti tunnust.
-- IS NOT DISTINCT FROM võimaldab korrektselt võrrelda ka NULL väärtusi.

UPDATE fact_rides fr
SET pricing_context_key = dpc.pricing_context_key
FROM dim_pricing_context dpc
WHERE dpc.prediction_price_type IS NOT DISTINCT FROM fr.prediction_price_type
  AND dpc.change_reason_pricing IS NOT DISTINCT FROM fr.change_reason_pricing
  AND dpc.entered_by IS NOT DISTINCT FROM fr.entered_by;

-- Kontrollin, kas kõik 4166 sõitu said pricing_context_key väärtuse.
-- Oodatav tulemus on 0.

SELECT COUNT(*) AS missing_pricing_context_key
FROM fact_rides
WHERE pricing_context_key IS NULL;

-- Seon fact_rides.device_key veeru dim_device tabeliga.
-- See tagab, et fact_rides tabelis saab kasutada ainult
-- dim_device tabelis olemasolevaid device_key väärtusi.

ALTER TABLE fact_rides
ADD CONSTRAINT fact_rides_device_key_fkey
FOREIGN KEY (device_key)
REFERENCES dim_device(device_key);

-- Seon fact_rides.app_version_key veeru dim_app_version tabeliga.
-- Selle kaudu saab iga sõidu siduda vastava
-- rider + driver app-versiooni kombinatsiooniga.

ALTER TABLE fact_rides
ADD CONSTRAINT fact_rides_app_version_key_fkey
FOREIGN KEY (app_version_key)
REFERENCES dim_app_version(app_version_key);

-- Seon fact_rides.pricing_context_key veeru dim_pricing_context tabeliga.
-- Selle kaudu saab iga sõidu siduda vastava hinnastamise kontekstiga.

ALTER TABLE fact_rides
ADD CONSTRAINT fact_rides_pricing_context_key_fkey
FOREIGN KEY (pricing_context_key)
REFERENCES dim_pricing_context(pricing_context_key);

-- Kuvan fact_rides tabeli kõik Foreign Key seosed.
-- Kontrollin, et uued device, app version ja pricing context
-- seosed oleksid edukalt loodud.

SELECT
    conname AS constraint_name,
    pg_get_constraintdef(oid) AS definition
FROM pg_constraint
WHERE conrelid = 'fact_rides'::regclass
  AND contype = 'f'
ORDER BY conname;

-- Eemaldan fact_rides tabeli vana Foreign Key seose dim_app_device tabeliga.
-- Seda pole enam vaja, sest device ja app version on nüüd
-- eraldi dimensioonides.

ALTER TABLE fact_rides
DROP CONSTRAINT fact_rides_app_device_key_fkey;

-- Eemaldan fact_rides tabelist vana app_device_key veeru.
-- Selle asemel kasutame nüüd device_key ja app_version_key võtmeid.

ALTER TABLE fact_rides
DROP COLUMN app_device_key;

-- Eemaldan vana dim_app_device tabeli.
-- Selle info on nüüd jagatud dim_device ja dim_app_version tabelitesse.

DROP TABLE dim_app_device;

-- Kontrollin, et fact_rides kõik dimensioonivõtmed oleksid täidetud.
-- Kõigi tulemuste oodatav väärtus on 0.

SELECT
    COUNT(*) FILTER (WHERE date_key IS NULL) AS missing_date,
    COUNT(*) FILTER (WHERE order_key IS NULL) AS missing_order,
    COUNT(*) FILTER (WHERE device_key IS NULL) AS missing_device,
    COUNT(*) FILTER (WHERE app_version_key IS NULL) AS missing_app_version,
    COUNT(*) FILTER (WHERE pricing_context_key IS NULL) AS missing_pricing_context
FROM fact_rides;

-- Eemaldan fact_rides tabelist hinnastamise konteksti kirjeldavad veerud,
-- sest need asuvad nüüd dim_pricing_context tabelis.
-- fact_rides seos nendega säilib pricing_context_key kaudu.

ALTER TABLE fact_rides
DROP COLUMN prediction_price_type,
DROP COLUMN change_reason_pricing,
DROP COLUMN entered_by;

-- Eemaldan fact_rides tabelist väljad,
-- mis asuvad nüüd dim_pricing_context tabelis.

ALTER TABLE fact_rides
DROP COLUMN prediction_price_type,
DROP COLUMN change_reason_pricing,
DROP COLUMN entered_by;

-- Kontrollin, millised veerud on praegu fact_rides tabelis olemas.
-- Nii näeme, kas pricing context väljad on juba eemaldatud.

SELECT column_name
FROM information_schema.columns
WHERE table_name = 'fact_rides'
ORDER BY ordinal_position;

-- Lisan dim_order tabelisse tunnuse,
-- mis näitab, kas orderil oli vähemalt üks overpaid ride ticket.

ALTER TABLE dim_order
ADD COLUMN had_overpaid_ride_ticket INT;

-- Täidan tunnuse fact_tickets andmete põhjal.
-- MAX annab tulemuseks 1, kui orderil oli vähemalt üks
-- overpaid_ride_ticket = 1.
-- Kui kõik orderi ticketid olid 0, saab order väärtuseks 0.

UPDATE dim_order d
SET had_overpaid_ride_ticket = x.had_overpaid
FROM (
    SELECT
        order_key,
        MAX(overpaid_ride_ticket) AS had_overpaid
    FROM fact_tickets
    GROUP BY order_key
) x
WHERE d.order_key = x.order_key;

-- Kontrollin orderite jaotust selle järgi,
-- kas orderil oli vähemalt üks overpaid ticket.

SELECT
    had_overpaid_ride_ticket,
    COUNT(*) AS orders
FROM dim_order
GROUP BY had_overpaid_ride_ticket
ORDER BY had_overpaid_ride_ticket;

-- Kontrollin, kas kõik orderid said overpaid tunnuse.
-- Oodatav tulemus: 0.

SELECT COUNT(*) AS missing_overpaid_flag
FROM dim_order
WHERE had_overpaid_ride_ticket IS NULL;

-- Kontrollin had_overpaid_ride_ticket väärtuste jaotust.
-- Ootan ainult väärtuseid 0 ja 1.

SELECT
    had_overpaid_ride_ticket,
    COUNT(*) AS orders
FROM dim_order
GROUP BY had_overpaid_ride_ticket
ORDER BY had_overpaid_ride_ticket;

-- Kontrollin, kas dim_order overpaid tunnus vastab
-- fact_tickets tabelis olevale infole.
-- Oodatav tulemus: 0.

SELECT COUNT(*) AS mismatches
FROM dim_order d
JOIN (
    SELECT
        order_key,
        MAX(overpaid_ride_ticket) AS expected_overpaid
    FROM fact_tickets
    GROUP BY order_key
) t
    ON d.order_key = t.order_key
WHERE d.had_overpaid_ride_ticket <> t.expected_overpaid;

-- Kontrollin, et ühegi orderi overpaid tunnus poleks NULL.
-- Oodatav tulemus: 0.

-- Kontrollin, et ühegi orderi overpaid tunnus poleks NULL.
-- Oodatav tulemus: 0.

SELECT COUNT(*) AS missing_overpaid_flag
FROM dim_order
WHERE had_overpaid_ride_ticket IS NULL;