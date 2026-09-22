Andmetarkus kursuse grupitöö – grupp Takso

Andmete puhastamise ja korrastamise dokumentatsioon

Andmestik valmistati analüüsiks ette Pythonis Pandase abil. Puhastamise eesmärk oli parandada andmete kasutatavust ja kvaliteeti, säilitades samal ajal võimalikud anomaaliad, mis võivad olla olulised overcharge ticket'ite põhjuste edasises analüüsis.

Tehtud korrastused

* Kontrolliti andmestiku suurust, veerge ja andmetüüpe.
* `calc_created` teisendati datetime-formaati.
* Kuupäevast loodi analüüsi jaoks eraldi tunnused: `date`, `time`, `day_of_week`, `day_of_week_nr`, `month` ja `year`.
* Täielikult tühi `device_token` veerg eemaldati.
* Kontrolliti täielikke duplikaatridu – neid ei leitud.
* Kontrolliti võimalikke dubleerivaid veerge ning `order_id_new` ja `order_try_id_new` omavahelist seost.
* Kontrolliti korduvaid `order_id_new` väärtusi. Korduvaid tellimusi ei eemaldatud, sest sama tellimusega võivad olla seotud erinevad kirjed ja ticket'id.
* Kontrolliti kategooriliste tunnuste väärtusi ning võimalikke ebakõlasid.
* Analüüsiti puuduvaid väärtusi ja nende osakaalu.
