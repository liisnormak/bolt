-----------------------------------------------
--K1: Kui suur osa pöördumistest tuleb prediction-sõitudest, kui määrad arvutada tellimuse tasemel (4166 tellimust)?
---
--- H: prediction annab ~2/3 pöördumistest ja pöördumismäär on ~5× kõrgem.
--- → Otsus: kas fookus kitsendada ühele segmendile.
-----------------------------------------------

--**Samm 1. Kontrolli, et andmed on sees**

SELECT COUNT(*)                     AS ridu,
       COUNT(DISTINCT order_id_new) AS soite
FROM takso_andmed_clean;

---Tähendus: ridu on rohkem kui sõite, seega mõnel sõidul on mitu rida.


--**Samm 2. Uuri duplikaate**

SELECT order_id_new, COUNT(*) AS ridu
FROM takso_andmed_clean
GROUP BY order_id_new
HAVING COUNT(*) > 1
ORDER BY ridu DESC
LIMIT 10;

SELECT *
FROM takso_andmed_clean
WHERE order_id_new = 2241;   -- asendain ID-ga eelmisest tulemusest

--- Oodatav tulemus: 612 sõidul on rohkem kui 1 rida, maksimaalselt 6 rida.
----Sama sõidu read erinevad ainult veergudes `ticket_id_new` ja `overpaid_ride_ticket`.
--- Tähendus: **1 rida = 1 pöördumine, mitte 1 sõit.** Sõidud tuleb enne loendamist koondada, muidu loed pöördumisi topelt.


WITH soidud AS (
    SELECT order_id_new,
           MAX(prediction_price_type) AS hinnatyyp,
           MAX(overpaid_ride_ticket)  AS on_poordumine
    FROM takso_andmed_clean
    GROUP BY order_id_new
)
SELECT hinnatyyp,
       COUNT(*)                             AS soite,
       SUM(on_poordumine)                   AS poordumisega,
       ROUND(100.0 * AVG(on_poordumine), 1) AS maar_pct,
       ROUND(100.0 * SUM(on_poordumine)
             / SUM(SUM(on_poordumine)) OVER (), 1) AS osa_koigist_pct
FROM soidud
GROUP BY hinnatyyp
ORDER BY poordumisega DESC;


--**K1 vastus**
---- 309 sõitu 4166-st (7,4%) sai enammakse pöördumise.
---- `prediction`-hinnatüüp annab 66% neist sõitudest. 
---- Selle pöördumismäär (20,3%) on ~6× kõrgem kui `upfront` puhul (3,5%). Suurem osa sellest tuli turust, mitte hinnatüübis (K2 ajal tulnud järeldus).
---- Mitte-EL turul kaebavad ka upfront-sõitjad palju. Hinnatüübi puhas mõju on ca 1.5x, mitte 6x. 
---- Hüpotees leiab kinnitust: fookus kitsendada `prediction`-sõitudele (K2).



-----------------------------------------------
--- K2 Kas hinnatüüp ise põhjustab pöördumisi?
---
--- Kas prediction-sõitudel on pöördumismäär kõrgem kui upfront-sõitudel ka mitte-EL turul, sarnase distantsi ja kestuse juures?
--- Veerud: prediction_price_type, eu_indicator, distance, duration
--- H: Jah. Erinevus püsib ka siis, kui sõit kulges prognoosi järgi.
--- → Otsus: kas soovitada prediction-sõitude viimist upfront-hinnale.
-----------------------------------------------

CREATE VIEW soidud AS
SELECT order_id_new,
       MAX(prediction_price_type) AS hinnatyyp,
       MAX(eu_indicator)          AS eu,
       MAX(distance)              AS distants,
       MAX(duration)              AS kestus,
       MAX(predicted_distance)    AS prog_distants,
       MAX(predicted_duration)    AS prog_kestus,
       MAX(overpaid_ride_ticket)  AS on_poordumine
FROM takso_andmed_clean
GROUP BY order_id_new;


SELECT COUNT(*) FROM soidud;

---Samm 1. Võrdle hinnatüüpe EL ja mitte-EL turul

SELECT eu,
       hinnatyyp,
       COUNT(*)                             AS soite,
       SUM(on_poordumine)                   AS poordumisega,
       ROUND(100.0 * AVG(on_poordumine), 1) AS maar_pct
FROM soidud
WHERE hinnatyyp IN ('prediction', 'upfront')
GROUP BY eu, hinnatyyp
ORDER BY eu, hinnatyyp;

---Tähendus:
---EL-is prediction-sõite praktiliselt pole, seega võrdlus on võimalik ainult mitte-EL turul.
---Mitte-EL turul on erinevus 20,4% vs 13,4%.
---Edaspidi analüüsime ainult eu = 0.


---Samm 2. Kontrolli distantsi mõju
---Pikad sõidud võivad kaevata rohkem sõltumata hinnatüübist. Võrdleme sama pikkusega sõite.

SELECT CASE
         WHEN distants <  2000 THEN '1: alla 2 km'
         WHEN distants <  5000 THEN '2: 2-5 km'
         WHEN distants < 10000 THEN '3: 5-10 km'
         WHEN distants < 20000 THEN '4: 10-20 km'
         ELSE                       '5: 20+ km'
       END                                  AS vahemik,
       hinnatyyp,
       COUNT(*)                             AS soite,
       ROUND(100.0 * AVG(on_poordumine), 1) AS maar_pct
FROM soidud
WHERE eu = 0
  AND hinnatyyp IN ('prediction', 'upfront')
GROUP BY vahemik, hinnatyyp
ORDER BY vahemik, hinnatyyp;

--- Tähendus: prediction on kõrgem 4 vahemikus 5-st. Mida pikem sõit, seda suurem vahe.


--- Samm 3. Kontrolli kestuse mõju

SELECT CASE
         WHEN kestus <  600 THEN '1: alla 10 min'
         WHEN kestus < 1200 THEN '2: 10-20 min'
         WHEN kestus < 1800 THEN '3: 20-30 min'
         ELSE                    '4: 30+ min'
       END                                  AS vahemik,
       hinnatyyp,
       COUNT(*)                             AS soite,
       ROUND(100.0 * AVG(on_poordumine), 1) AS maar_pct
FROM soidud
WHERE eu = 0
  AND hinnatyyp IN ('prediction', 'upfront')
GROUP BY vahemik, hinnatyyp
ORDER BY vahemik, hinnatyyp;

--- Tähendus: lühikestel sõitudel vahet pole. Üle 20 minuti on prediction ~1,7× kõrgem.

--- Samm 4. Sõidud, mis kulgesid prognoosi järgi
--- Hüpoteesi tuum: kas prediction-sõitjad kaebavad rohkem ka siis, kui sõit läks täpselt plaani järgi?

SELECT hinnatyyp,
       COUNT(*)                             AS soite,
       SUM(on_poordumine)                   AS poordumisega,
       ROUND(100.0 * AVG(on_poordumine), 1) AS maar_pct
FROM soidud
WHERE eu = 0
  AND hinnatyyp IN ('prediction', 'upfront')
  AND ABS(distants / NULLIF(prog_distants, 0) - 1) <= 0.1
GROUP BY hinnatyyp;

--- Tähendus: kui distants vastab prognoosile, on prediction pöördumismäär ~3× kõrgem.

-- ** K2 vastus: Hüpotees leiab kinnitust: erinevus püsib ka sama turu, sarnase pikkuse ja prognoosipärase sõidu juures.**
--- Uus leid: mitte-EL turg on ise probleem. Seal kaebavad ka upfront-sõitjad 20× rohkem kui EL-is.
--- Otsus: soovitus viia prediction-sõidud upfront-hinnale on põhjendatud, aga see lahendab ainult osa probleemist. Mitte-EL turu enda põhjused vajavad eraldi uurimist.

--- Mõju järgmistele küsimustele: K3 peaks uurima ainult mitte-EL sõite.



-----------------------------------------------
---K3. Mis tõstab prediction-sõitude hinda üle ootuse?
--- Kas pöördumisega sõitudel on suurem kestuse või distantsi kõrvalekalle prognoosist?
--- Veerud: duration vs predicted_duration, distance vs predicted_distance, gps_confidence
--- H: Kestuse kõrvalekalle (ummikud, ootamine) mõjutab rohkem kui distants. Distantsi puhul on määr kõrge juba ±10% juures.
-- → Otsus: prognoosimudeli parandamine vs parem hinnainfo sõitjale.
-----------------------------------------------


--- Samm 0. Uuenda vaadet
--- Lisame vaatesse GPS-i ja valmis arvutatud kõrvalekalded, et hilisemad päringud oleksid lühemad.


CREATE OR REPLACE view soidud AS
SELECT order_id_new,
       MAX(prediction_price_type) AS hinnatyyp,
       MAX(eu_indicator)          AS eu,
       MAX(distance)              AS distants,
       MAX(duration)              AS kestus,
       MAX(predicted_distance)    AS prog_distants,
       MAX(predicted_duration)    AS prog_kestus,
       MAX(overpaid_ride_ticket)  AS on_poordumine,
       MAX(gps_confidence)        AS gps,
       MAX(distance) / NULLIF(MAX(predicted_distance), 0) - 1 AS dist_korv,
       MAX(duration) / NULLIF(MAX(predicted_duration), 0) - 1 AS kest_korv
FROM takso_andmed_clean
GROUP BY order_id_new;


SELECT COUNT(*)
FROM soidud
WHERE eu = 0
  AND hinnatyyp = 'prediction'
  AND dist_korv IS NOT NULL
  AND kest_korv IS NOT NULL;


--- Samm 1. Kas pöördumisega sõidud erinevad prognoosist rohkem?

SELECT on_poordumine,
       COUNT(*) AS soite,
       ROUND((100 * PERCENTILE_CONT(0.5)
              WITHIN GROUP (ORDER BY dist_korv))::numeric, 1) AS dist_korv_mediaan_pct,
       ROUND((100 * PERCENTILE_CONT(0.5)
              WITHIN GROUP (ORDER BY kest_korv))::numeric, 1) AS kest_korv_mediaan_pct
FROM soidud
WHERE eu = 0
  AND hinnatyyp = 'prediction'
  AND dist_korv IS NOT NULL
  AND kest_korv IS NOT NULL
GROUP BY on_poordumine;

---Tähendus:
----Kestus: kõik sõidud kestavad ~40% kauem kui prognoos, sõltumata pöördumisest. Kestus ei erista kaebajaid.
----Distants: pöördumisega sõitudel on mediaanne kõrvalekalle veidi suurem. Täpsem pilt tuleb vahemikest (samm 2).


--- Samm 2. Pöördumismäär distantsi kõrvalekalde järgi

SELECT CASE
         WHEN dist_korv <= -0.10 THEN '1: alla -10%'
         WHEN dist_korv <=  0.10 THEN '2: ±10%'
         WHEN dist_korv <=  0.25 THEN '3: +10..25%'
         WHEN dist_korv <=  0.50 THEN '4: +25..50%'
         WHEN dist_korv <=  1.00 THEN '5: +50..100%'
         ELSE                         '6: üle +100%'
       END                                  AS vahemik,
       COUNT(*)                             AS soite,
       ROUND(100.0 * AVG(on_poordumine), 1) AS maar_pct
FROM soidud
WHERE eu = 0
  AND hinnatyyp = 'prediction'
  AND dist_korv IS NOT NULL
  AND kest_korv IS NOT NULL
GROUP BY vahemik
ORDER BY vahemik;

--- Tähendus: kuni +50% on määr ~9–19%. Üle +100% kaebab iga teine sõitja.

--- Samm 3. Pöördumismäär kestuse kõrvalekalde järgi. Sama päring, aga dist_korv asemel kest_korv:

SELECT CASE
         WHEN kest_korv <= -0.10 THEN '1: alla -10%'
         WHEN kest_korv <=  0.10 THEN '2: ±10%'
         WHEN kest_korv <=  0.25 THEN '3: +10..25%'
         WHEN kest_korv <=  0.50 THEN '4: +25..50%'
         WHEN kest_korv <=  1.00 THEN '5: +50..100%'
         ELSE                         '6: üle +100%'
       END                                  AS vahemik,
       COUNT(*)                             AS soite,
       ROUND(100.0 * AVG(on_poordumine), 1) AS maar_pct
FROM soidud
WHERE eu = 0
  AND hinnatyyp = 'prediction'
  AND dist_korv IS NOT NULL
  AND kest_korv IS NOT NULL
GROUP BY vahemik
ORDER BY vahemik;

--- Samm 4. GPS-i mõju

SELECT gps,
       COUNT(*)                             AS soite,
       SUM(on_poordumine)                   AS poordumisega,
       ROUND(100.0 * AVG(on_poordumine), 1) AS maar_pct
FROM soidud
WHERE eu = 0
  AND hinnatyyp = 'prediction'
  AND dist_korv IS NOT NULL
  AND kest_korv IS NOT NULL
GROUP BY gps;

--- Tähendus: halva GPS-iga sõidud annavad 2/3 pöördumistest ja nende määr on ~2,8× kõrgem. 42% prediction-sõitudest on halva GPS-iga.

--- Samm 5. GPS × suur distantsi kõrvalekalle
--- Kas suur kõrvalekalle on probleem iseenesest või ainult koos halva GPS-iga?

SELECT CASE WHEN dist_korv > 0.5 THEN 'üle +50%' ELSE 'kuni +50%' END AS dist_korv,
       gps,
       COUNT(*)                             AS soite,
       ROUND(100.0 * AVG(on_poordumine), 1) AS maar_pct
FROM soidud
WHERE eu = 0
  AND hinnatyyp = 'prediction'
  AND dist_korv IS NOT NULL
  AND kest_korv IS NOT NULL
GROUP BY 1, gps
ORDER BY 1, gps;


--- Tähendus: suur distantsi kõrvalekalle tõstab pöördumisi ainult halva GPS-iga. Hea GPS-iga on see sama madal kui tavaliselt. Tõenäoliselt tähendab see, et hea GPS-i korral on pikem teekond päriselt sõidetud, halva GPS-i korral aga mõõtmisviga.


-----------------------------------------------
---K4. Kus on taluvuspiir?
----Mis hinnavahe % juures pöördumise tõenäosus järsult tõuseb? Eraldi upfront- ja prediction-sõitudele (taastatud eelhinnaga, meetod A).
----H: prediction-sõitudel on piir madalam, sest sõitja ei tea täpset hinda.
---- → Otsus: hinnalagi, teavitus sõidu ajal või automaatne tagasimakse.
-----------------------------------------------


-- Samm 0. Lisa vaatesse hinnad
-- Sama vaade nagu K3-s, lõppu lisanduvad 2 veergu.

CREATE OR REPLACE VIEW soidud AS
SELECT order_id_new,
       MAX(prediction_price_type) AS hinnatyyp,
       MAX(eu_indicator)          AS eu,
       MAX(distance)              AS distants,
       MAX(duration)              AS kestus,
       MAX(predicted_distance)    AS prog_distants,
       MAX(predicted_duration)    AS prog_kestus,
       MAX(overpaid_ride_ticket)  AS on_poordumine,
       MAX(gps_confidence)        AS gps,
       MAX(distance) / NULLIF(MAX(predicted_distance), 0) - 1 AS dist_korv,
       MAX(duration) / NULLIF(MAX(predicted_duration), 0) - 1 AS kest_korv,
       MAX(metered_price)         AS hind,
       MAX(upfront_price)         AS eelhind
FROM takso_andmed_clean
GROUP BY order_id_new;

SELECT * FROM soidud LIMIT 5;

--- Samm 1. Leia hind meetri kohta ja miinimumtasu

SELECT PERCENTILE_CONT(0.5)
       WITHIN GROUP (ORDER BY eelhind / prog_distants) AS hind_meetri_kohta,
       COUNT(*)                                        AS soite
FROM soidud
WHERE eu = 0
  AND hinnatyyp = 'upfront'
  AND prog_distants > 0
  AND eelhind IS NOT NULL;

SELECT eelhind, COUNT(*) AS soite
FROM soidud
WHERE eu = 0 AND hinnatyyp = 'upfront'
GROUP BY eelhind
ORDER BY soite DESC
LIMIT 5;

--- Samm 2. Kontrolli, kas valem töötab
---- Testime valemit upfront-sõitudel, kus päris eelhind on teada.

SELECT ROUND((100 * PERCENTILE_CONT(0.5) WITHIN GROUP (
         ORDER BY ABS(GREATEST(6000, 1.4305 * prog_distants) / eelhind - 1)
       ))::numeric, 1) AS mediaanne_viga_pct
FROM soidud
WHERE eu = 0
  AND hinnatyyp = 'upfront'
  AND prog_distants > 0
  AND eelhind IS NOT NULL;

---Oodatav tulemus: 7.7
-- Tähendus: valem eksib tüüpiliselt ~8%. Piisavalt täpne, et kasutada prediction-sõitudel.

--- Samm 3. Loo hinnavahe vaade

CREATE VIEW hinnavahe AS
SELECT order_id_new,
       hinnatyyp,
       on_poordumine,
       gps,
       hind,
       CASE WHEN hinnatyyp = 'upfront' THEN eelhind
            ELSE GREATEST(6000, 1.4305 * prog_distants)
       END AS oodatud_hind,
       hind / CASE WHEN hinnatyyp = 'upfront' THEN eelhind
                   ELSE GREATEST(6000, 1.4305 * prog_distants)
              END - 1 AS vahe
FROM soidud
WHERE eu = 0
  AND hinnatyyp IN ('prediction', 'upfront')
  AND prog_distants > 0
  AND hind IS NOT NULL
  AND (hinnatyyp = 'prediction' OR eelhind IS NOT NULL);



SELECT hinnatyyp, COUNT(*) FROM hinnavahe GROUP BY hinnatyyp;


--- Samm 4. Kas kaebajad maksid rohkem?

SELECT hinnatyyp,
       on_poordumine,
       COUNT(*) AS soite,
       ROUND((100 * PERCENTILE_CONT(0.5)
              WITHIN GROUP (ORDER BY vahe))::numeric, 1) AS vahe_mediaan_pct
FROM hinnavahe
GROUP BY hinnatyyp, on_poordumine
ORDER BY hinnatyyp, on_poordumine;

---Tähendus: kaebajad maksid tüüpiliselt 13–17% üle oodatu. Mittekaebajad 3–6%.


---Samm 5. Pöördumismäär hinnavahe järgi

SELECT CASE
         WHEN vahe <= -0.10 THEN '1: alla -10%'
         WHEN vahe <=  0.10 THEN '2: ±10%'
         WHEN vahe <=  0.25 THEN '3: +10..25%'
         WHEN vahe <=  0.50 THEN '4: +25..50%'
         WHEN vahe <=  1.00 THEN '5: +50..100%'
         ELSE                    '6: üle +100%'
       END                                  AS vahemik,
       hinnatyyp,
       COUNT(*)                             AS soite,
       ROUND(100.0 * AVG(on_poordumine), 1) AS maar_pct
FROM hinnavahe
GROUP BY vahemik, hinnatyyp
ORDER BY vahemik, hinnatyyp;


--- Tähendus:
----Piir on mõlemal üle +100%. Seal määr ligikaudu kahekordistub.
----prediction on +10…+100% vahel ühtlaselt ~20%, upfront ~9–15%. Madalamat piiri prediction jaoks ei ole.
----Üllatus: isegi kui sõitja maksis vähem kui oodatud, kaebas ~13%. Osa pöördumisi ei ole seotud hinnavahega.
----Upfront-vahemikes on 65–90 sõitu, seega vahe ±5 protsendipunkti ei ole usaldusväärne. Järsk hüpe üle +100% on seda.


---Samm 6. Kui suure osa pöördumistest katab piir +100%?

SELECT hinnatyyp,
       COUNT(*) FILTER (WHERE vahe > 1)           AS soite_ule_piiri,
       SUM(on_poordumine) FILTER (WHERE vahe > 1) AS poordumisi_ule_piiri,
       SUM(on_poordumine)                         AS poordumisi_kokku
FROM hinnavahe
GROUP BY hinnatyyp;D

---Kokku: 71 pöördumist 292-st = ~24%.

-----------------------------------------------
---K5. Välistuskontroll: pettus ja andmekvaliteet
----Kas sõitjate pettus või andmevead (duplikaadid, puuduvad eelhinnad upfront_destination_changed sõitudel) seletavad olulise osa pöördumistest?
----H: Ei. Positiivse skooriga sõitjatel pöördumisi pole.
----→ Otsus: kinnitada, et järeldused ei põhine moonutatud andmetel.
-----------------------------------------------


-- Samm 0. Lisa vaatesse pettuse ja kehtivuse veerud
-- Sama vaade nagu K4-s, lõppu lisanduvad 3 veergu.

CREATE OR REPLACE VIEW soidud AS
SELECT order_id_new,
       MAX(prediction_price_type) AS hinnatyyp,
       MAX(eu_indicator)          AS eu,
       MAX(distance)              AS distants,
       MAX(duration)              AS kestus,
       MAX(predicted_distance)    AS prog_distants,
       MAX(predicted_duration)    AS prog_kestus,
       MAX(overpaid_ride_ticket)  AS on_poordumine,
       MAX(gps_confidence)        AS gps,
       MAX(distance) / NULLIF(MAX(predicted_distance), 0) - 1 AS dist_korv,
       MAX(duration) / NULLIF(MAX(predicted_duration), 0) - 1 AS kest_korv,
       MAX(metered_price)         AS hind,
       MAX(upfront_price)         AS eelhind,
       MAX(fraud_score)           AS pettus_skoor,
       MAX(fraud_score_status)    AS pettus_staatus,
       BOOL_OR(is_invalid_ride)   AS kehtetu
FROM takso_andmed_clean
GROUP BY order_id_new;

SELECT * FROM soidud LIMIT 5;


-- Samm 1. Duplikaatide mõju

SELECT SUM(overpaid_ride_ticket)                    AS poordumise_ridu,
       COUNT(DISTINCT order_id_new)
         FILTER (WHERE overpaid_ride_ticket = 1)    AS poordumisega_soite,
       COUNT(DISTINCT ticket_id_new)                AS unikaalseid_ticket_id,
       MIN(ticket_id_new)                           AS min_id,
       MAX(ticket_id_new)                           AS max_id
FROM takso_andmed_clean;

---Tähendus:Reatasemel oleks pöördumisi 337, sõidutasemel 309. 24 sõidul oli mitu enammakse pöördumist. K1-s tehtud koondamine väldib topeltloendust. ✓
---Uus piirang:ticket_id_new on igal real olemas ja jookseb 0…4942 järjest. Ma ei ole kindel, aga tõenäoliselt on see anonüümimisel loodud reanumber. Siis ei saa kindlaks teha, kas andmestik sisaldab kõiki sõite või ainult sõite, millel oli mingi pöördumine. Teisel juhul tähendab "pöördumismäär" hoopis: milline osa pöördumistest puudutas enammakset.

-- Samm 2. Puuduvad ja kahtlased andmed

SELECT 'upfront_destination_changed' AS probleem, COUNT(*) AS soite, SUM(on_poordumine) AS poordumisi
FROM soidud WHERE hinnatyyp = 'upfront_destination_changed'
UNION ALL
SELECT 'taksomeetri hind puudub', COUNT(*), SUM(on_poordumine)
FROM soidud WHERE hind IS NULL
UNION ALL
SELECT 'hinnatüüp puudub', COUNT(*), SUM(on_poordumine)
FROM soidud WHERE hinnatyyp IS NULL
UNION ALL
SELECT 'distants üle 100 km', COUNT(*), SUM(on_poordumine)
FROM soidud WHERE distants > 100000
UNION ALL
SELECT 'kehtetu sõit', COUNT(*), SUM(on_poordumine)
FROM soidud WHERE kehtetu;


--- Tähendus: kõik probleemsed read kokku puudutavad 5 pöördumist 309-st (~1,6%). Järeldusi need ei muuda.


--- Samm 3. Pettuse staatus

SELECT pettus_staatus,
       COUNT(*)                             AS soite,
       SUM(on_poordumine)                   AS poordumisega,
       ROUND(100.0 * AVG(on_poordumine), 1) AS maar_pct
FROM soidud
GROUP BY pettus_staatus
ORDER BY soite DESC;

--- Tähendus: 41 sõitu on liiga vähe järelduseks (vt varasem arutelu: tegelik määr võib olla kuni ~7%). Seepärast samm 4.

--- Samm 4. Kas kõrgem skoor tähendab rohkem pöördumisi?
--- Jagame kõik skooriga sõidud nelja võrdse grupi, madalamast kõrgemani. Nii on igas grupis ~480 sõitu, mitte 41.

WITH s AS (
    SELECT pettus_skoor,
           on_poordumine,
           NTILE(4) OVER (ORDER BY pettus_skoor) AS neljandik
    FROM soidud
    WHERE pettus_skoor IS NOT NULL
)
SELECT neljandik,
       COUNT(*)                             AS soite,
       MIN(pettus_skoor)                    AS skoor_min,
       MAX(pettus_skoor)                    AS skoor_max,
       SUM(on_poordumine)                   AS poordumisega,
       ROUND(100.0 * AVG(on_poordumine), 1) AS maar_pct
FROM s
GROUP BY neljandik
ORDER BY neljandik;

--- Tähendus: trendi pole. Kõrgema riskiga sõitjad ei kaeba rohkem. Pettuse hüpotees lükatakse ümber ka suuremal valimil.

--- Samm 5. Miks on "Missing" määr 13,1%?

SELECT hinnatyyp,
       COUNT(*)                                          AS soite,
       COUNT(*) FILTER (WHERE pettus_staatus = 'Missing') AS skoor_puudub,
       ROUND(100.0 * COUNT(*) FILTER (WHERE pettus_staatus = 'Missing')
             / COUNT(*), 1)                              AS puudub_pct
FROM soidud
GROUP BY hinnatyyp
ORDER BY soite desc

--- Tähendus: skoor puudub peaaegu kõigil prediction-sõitudel. Kõrge määr tuleb hinnatüübist (K2), mitte pettusest.


--- Samm 6. Tundlikkusanalüüs: kas K2 ja K3 järeldused püsivad? Arvutame põhinumbrid uuesti, jättes välja kõik kahtlased sõidud.

SELECT hinnatyyp,
       COUNT(*)                             AS soite,
       SUM(on_poordumine)                   AS poordumisega,
       ROUND(100.0 * AVG(on_poordumine), 1) AS maar_pct
FROM soidud
WHERE eu = 0
  AND hinnatyyp IN ('prediction', 'upfront')
  AND NOT kehtetu
  AND hind IS NOT NULL
  AND distants <= 100000
  AND pettus_staatus <> 'Positive'
GROUP BY hinnatyyp;

--- Tähendus: järeldused ei muutu.


