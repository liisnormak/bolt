-- =====================================================================
-- Bolt andmete puhastus ja korrastus — PostgreSQL
-- Grain: 1 rida = 1 tugipilet (ticket_id_new). GRAIN JÄÄB PUUTUMATA.
-- Ridu kokku: 4943 (sisse ja välja).
--
-- Töövoog: bolt_raw (toores TEXT) -> bolt_clean (tüübitud + lipud)
-- Käivita DBeaveris või psql'is järjest ülalt alla.
-- =====================================================================


-- ---------------------------------------------------------------------
-- 0. Puhas algus
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS bolt_clean;
DROP TABLE IF EXISTS bolt_raw;


-- ---------------------------------------------------------------------
-- 1. STAGING: kõik veerud TEXT-ina, et messy CSV laeks ilma vigadeta
--    (nt calc_created "2020-02-02 3:37:31" ühekohaline tund)
-- ---------------------------------------------------------------------
CREATE TABLE bolt_raw (
    order_id_new            TEXT,
    order_try_id_new        TEXT,
    calc_created            TEXT,
    metered_price           TEXT,
    upfront_price           TEXT,
    distance                TEXT,
    duration                TEXT,
    gps_confidence          TEXT,
    entered_by              TEXT,
    b_state                 TEXT,
    dest_change_number      TEXT,
    prediction_price_type   TEXT,
    predicted_distance      TEXT,
    predicted_duration      TEXT,
    change_reason_pricing   TEXT,
    ticket_id_new           TEXT,
    device_token            TEXT,   -- laetakse, aga clean-tabelisse EI lähe (100% tühi)
    rider_app_version       TEXT,
    order_state             TEXT,
    order_try_state         TEXT,
    driver_app_version      TEXT,
    driver_device_uid_new   TEXT,
    device_name             TEXT,
    eu_indicator            TEXT,
    overpaid_ride_ticket    TEXT,
    fraud_score             TEXT
);

-- LAADIMINE — vali üks:
-- (a) server-side, fail PostgreSQL serveris:
-- COPY bolt_raw FROM '/absoluutne/tee/2026_Bolt_data.csv'
--     WITH (FORMAT csv, HEADER true);
--
-- (b) client-side (DBeaver / psql), fail sinu masinas:
-- \copy bolt_raw FROM '/absoluutne/tee/2026_Bolt_data.csv' WITH (FORMAT csv, HEADER true)
--
-- ASENDA tee. Peale laadimist: SELECT count(*) FROM bolt_raw;  -- ootab 4943


-- ---------------------------------------------------------------------
-- 2. CLEAN: tüübitud tabel + tuletatud lipud
--    Abifunktsioon: NULLIF(trim(x),'') muudab tühja stringi NULL-iks
--    enne tüübiteisendust.
-- ---------------------------------------------------------------------
CREATE TABLE bolt_clean AS
SELECT
    -- ---- identifikaatorid --------------------------------------------
    NULLIF(trim(ticket_id_new),'')::bigint        AS ticket_id,        -- PK, grain
    NULLIF(trim(order_id_new),'')::bigint          AS order_id,
    NULLIF(trim(order_try_id_new),'')::bigint      AS order_try_id,

    -- ---- P5: kuupäev tekstist datetime'iks ---------------------------
    NULLIF(trim(calc_created),'')::timestamp       AS calc_created,

    -- ---- hinnad ------------------------------------------------------
    NULLIF(trim(metered_price),'')::numeric        AS metered_price,
    -- P2/upfront: NULL = "upfront-hinda ei eksisteerinud" (ennustushind).
    --            EI täideta, jääb NULL teadlikult.
    NULLIF(trim(upfront_price),'')::numeric         AS upfront_price,

    -- ---- P1: VALUUTA selge tähistus ----------------------------------
    NULLIF(trim(eu_indicator),'')::smallint         AS eu_indicator,
    CASE NULLIF(trim(eu_indicator),'')::smallint
         WHEN 1 THEN 'EUR'
         WHEN 0 THEN 'non_EUR'     -- tõenäoliselt Aafrika turg (TECNO/itel/Infinix seadmed)
    END                                             AS currency_group,

    -- ---- sõidu mõõdikud ----------------------------------------------
    NULLIF(trim(distance),'')::integer              AS distance,
    NULLIF(trim(duration),'')::integer              AS duration,
    NULLIF(trim(predicted_distance),'')::integer    AS predicted_distance,
    NULLIF(trim(predicted_duration),'')::integer    AS predicted_duration,

    -- ---- P3: vigased sõidud — LIPP, EI KUSTUTATA ---------------------
    (COALESCE(NULLIF(trim(distance),'')::integer, 0) <= 0
     OR COALESCE(NULLIF(trim(duration),'')::integer, 0) <= 0) AS is_invalid_ride,

    -- ---- olek / metaandmed -------------------------------------------
    NULLIF(trim(gps_confidence),'')::smallint       AS gps_confidence,
    NULLIF(trim(entered_by),'')                     AS entered_by,
    NULLIF(trim(b_state),'')                        AS b_state,
    NULLIF(trim(dest_change_number),'')::integer    AS dest_change_number,
    NULLIF(trim(prediction_price_type),'')          AS prediction_price_type,

    -- change_reason_pricing: tühi = muutust polnud (mitte viga) -> 'no_change'
    COALESCE(NULLIF(trim(change_reason_pricing),''), 'no_change') AS change_reason_pricing,

    NULLIF(trim(rider_app_version),'')              AS rider_app_version,
    NULLIF(trim(order_state),'')                    AS order_state,
    NULLIF(trim(order_try_state),'')                AS order_try_state,
    NULLIF(trim(driver_app_version),'')             AS driver_app_version,
    NULLIF(trim(driver_device_uid_new),'')::bigint  AS driver_device_uid,
    NULLIF(trim(device_name),'')                    AS device_name,
    NULLIF(trim(overpaid_ride_ticket),'')::smallint AS overpaid_ride_ticket,

    -- ---- P4: fraud_score PUUTUMATA (sh negatiivsed, NULL jääb NULL) ---
    NULLIF(trim(fraud_score),'')::integer           AS fraud_score

    -- device_token: TAHTLIKULT VÄLJA JÄETUD (100% tühi)
FROM bolt_raw;


-- ---------------------------------------------------------------------
-- 3. Võti + indeksid
-- ---------------------------------------------------------------------
ALTER TABLE bolt_clean ADD CONSTRAINT pk_bolt_clean PRIMARY KEY (ticket_id);
CREATE INDEX ix_bolt_order        ON bolt_clean (order_id);
CREATE INDEX ix_bolt_currency     ON bolt_clean (currency_group);
CREATE INDEX ix_bolt_invalid      ON bolt_clean (is_invalid_ride);
CREATE INDEX ix_bolt_created      ON bolt_clean (calc_created);


-- ---------------------------------------------------------------------
-- 4. Veergude dokumentatsioon (näeb DBeaveris veeru kommentaarina)
-- ---------------------------------------------------------------------
COMMENT ON TABLE  bolt_clean IS 'Bolt puhastatud. Grain: 1 rida = 1 pilet (ticket_id). 4943 rida.';
COMMENT ON COLUMN bolt_clean.currency_group        IS 'EUR (eu_indicator=1) vs non_EUR (=0, tõen. Aafrika). Hinnad EI ole valuutade üleselt võrreldavad.';
COMMENT ON COLUMN bolt_clean.upfront_price         IS 'NULL = upfront-hinda ei eksisteerinud (ennustushind). Teadlik NULL.';
COMMENT ON COLUMN bolt_clean.is_invalid_ride       IS 'TRUE kui distance<=0 VÕI duration<=0. Ridu ei kustutatud, ainult märgistatud.';
COMMENT ON COLUMN bolt_clean.change_reason_pricing IS 'no_change = hinnamuutust polnud (algne NULL).';
COMMENT ON COLUMN bolt_clean.fraud_score           IS 'Toores, muutmata (sh negatiivsed). Tähendus kinnitamata — kontrolli allikast enne kasutust.';


-- ---------------------------------------------------------------------
-- 5. Valideerimine — käivita ja võrdle ootustega
-- ---------------------------------------------------------------------
-- Ootused:
--   ridu = 4943 | order_id unikaalseid = 4166
--   EUR = 2770  | non_EUR = 2173
--   is_invalid_ride TRUE = 64
--   change_reason no_change = 4645
--   fraud_score NULL = 2759 (säilib)
SELECT
    count(*)                                          AS read_kokku,
    count(DISTINCT order_id)                          AS tellimusi,
    count(*) FILTER (WHERE currency_group='EUR')      AS eur,
    count(*) FILTER (WHERE currency_group='non_EUR')  AS non_eur,
    count(*) FILTER (WHERE is_invalid_ride)           AS vigaseid,
    count(*) FILTER (WHERE change_reason_pricing='no_change') AS no_change,
    count(*) FILTER (WHERE fraud_score IS NULL)       AS fraud_null
FROM bolt_clean;


-- ---------------------------------------------------------------------
-- 6. NÄIDISPÄRINGUD (grain'i õige kasutus)
-- ---------------------------------------------------------------------
-- (a) Käive SÕIDU tasandil — dedup order_id peale, valuutad eraldi:
-- SELECT currency_group, count(*) AS soite, sum(metered_price) AS kaive
-- FROM (SELECT DISTINCT ON (order_id) order_id, currency_group, metered_price
--       FROM bolt_clean ORDER BY order_id, ticket_id) s
-- GROUP BY currency_group;
--
-- (b) Vaidlused PILETI tasandil — kõik read, ära dedup:
-- SELECT gps_confidence, count(*) piletid,
--        avg(overpaid_ride_ticket::numeric) overpaid_maar
-- FROM bolt_clean GROUP BY gps_confidence;
