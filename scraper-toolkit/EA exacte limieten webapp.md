EA maakt de exacte limieten voor de EA FC (voorheen FIFA) Web App en Companion App bewust **niet openbaar** om te voorkomen dat bot-ontwikkelaars hun software net onder de grens programmeren.

Toch zijn vanuit de Ultimate Team-community de vaste grenzen en veilige richtlijnen vrij nauwkeurig bekend. Hieronder staat het overzicht per categorie:

---

### 1. Limieten voor Snipen & Zoeken (Search Requests)

Bij het snipen stuur je bij elke zoekopdracht of "Koop nu"-poging een request naar de servers van EA.

- **Zoeksnelheid:** Richtlijn is **maximaal 15 tot 20 zoekopdrachten per minuut**. Als je sneller zoekt (of constant op dezelfde knoppen ramt), detecteert het algoritme dit als bot-activiteit.
- **Totaal per uur:** Naar schatting ligt de limiet rond de **500 tot 1000 requests per uur**.
- **Gevolg bij overschrijding:**
  1. Eerst verschijnt er vaak een **CAPTCHA** (beveiligingspuzzel).
  2. Blijf je te snel doorgaan, dan krijg je een **Softban** (foutmeldingen zoals _"Er is een fout opgetreden"_ of _"Kan zoekopdracht niet voltooien"_).

---

### 2. Limieten voor Mass Bidding (Bieden)

- **Actieve biedingen (Transfer Targets):** Je kunt **maximaal 50 actieve biedingen** tegelijk hebben openstaan. Pas wanneer veilingen zijn afgelopen en verwerkt, komt er weer ruimte vrij.
- **Snelheid van bieden:** Bied niet met extreme tussenpozen (bijv. binnen 30 seconden op 50 spelers). Houd minimaal **2 tot 3 seconden** tussen opeenvolgende biedingen aan.
- **Gevolg bij overschrijding:** Een tijdelijke biedblokkade (_"There was an error with your bid"_).

---

### 3. Transferlijst & Relisten

- **Transferlijst capaciteit:** Je kunt maximaal **100 items** tegelijk te koop hebben staan.
- **Relist All-knop:** Het gebruik van de knop _"Alles opnieuw aanbieden"_ is veilig en telt als één enkele serveractie.
- **Handmatig relisten:** Als je 100 items razendsnel handmatig één voor één met gewijzigde prijzen aanbiedt, kan dit wél meetellen voor je requests-per-minuut limiet.

---

### 4. Niet-toegewezen items (Unassigned Pile)

- Op de Web App worden er **maximaal 5 niet-toegewezen items** getoond.
- Zodra je niet-toegewezen items hebt, blokkeert de Web App het openen van nieuwe packs totdat je deze items hebt verwerkt (op console kun je met een glitch een oneindige unassigned-rij opbouwen, maar op de Web App blokkeert dit de winkelinterface).

---

### 5. Hoe werken de Softbans en hoe los je ze op?

Wanneer je over een limiet heen gaat, deelt EA meestal een **Softban** uit:

| Duur Softban        | Oorzaak                                                               |
| :------------------ | :-------------------------------------------------------------------- |
| **15 – 30 minuten** | Eerste overtreding door te snel zoeken/bieden.                        |
| **1 – 2 uur**       | Herhaaldelijk de limiet opzoeken na een eerdere softban.              |
| **12 – 24 uur**     | Aanhoudend zwaar overschrijden van de limieten of falen van captchas. |

#### Tips om onder de radar te blijven:

1. **Neem pauzes:** Snip of bied maximaal 10 tot 15 minuten aan één stuk en neem daarna minimaal 5 minuten pauze.
2. **Varieer je acties:** Pas regelmatig je min/max-zoekprijs licht aan, wissel af tussen zoeken, bieden en transferlijst beheren.
3. **Wissel van netwerk bij een ban:** Een softban is vaak gekoppeld aan je IP-adres of apparaat. Schakel op je telefoon over van Wi-Fi naar 4G/5G (of log in op je console); vaak kun je daar direct weer verder handelen.
4. **Los CAPTCHA's direct en nauwkeurig op:** Fouten bij de CAPTCHA-controle verhogen de kans op een langdurige marktban aanzienlijk.

Als je je puur focust op **snipen en relisten**, loop je het hoogste risico op softbans. Snipen genereert namelijk de meeste server-requests per minuut (constant zoeken en direct *Buy Now* proberen).

Om maximaal resultaat te halen zonder geband te worden, gebruik je een **"3-Target Rotatie"** met strikte intervallen en time-outs.

---

### Het Pure Snipe & Relist Flowdiagram

```text
               +-------------------------------------------+
               |     FASE 1: Transferlijst Management      |
               | - Druk op "Relist All" (1 uur veilingen)  |
               | - Check hoeveel plekken vrij zijn         |
               +---------------------+---------------------+
                                     |
                                     v
               +-------------------------------------------+
               |   FASE 2: Snipen Target 1 (3 tot 4 min)   |
               | - Pace: 1 zoekopdracht per 3-4 seconden   |
               | - Toggle: Pas Min. Bod elke klik licht aan|
               +---------------------+---------------------+
                                     |
                                     v
                         [ Kaart gesniped? ]
                            /               \
                       JA  /                 \  NEE (na 4 min)
                          v                   v
            +--------------------+    +--------------------+
            | Direct Lijsten     |    | Switch Target      |
            | - Zet te koop      |    | - Wissel naar      |
            | - Ga door          |    |   Target 2 of 3    |
            +---------+----------+    +---------+----------+
                      \                       /
                       \                     /
                        v                   v
               +-------------------------------------------+
               |   FASE 3: Snipen Target 2 (3 tot 4 min)   |
               | - Zelfde tempo & prijs-toggle             |
               +---------------------+---------------------+
                                     |
                                     v
               +-------------------------------------------+
               |   FASE 4: Snipen Target 3 (3 tot 4 min)   |
               | - Zelfde tempo & prijs-toggle             |
               +---------------------+---------------------+
                                     |
                                     v
               +-------------------------------------------+
               |     FASE 5: Verplichte "Breuk" (3 min)    |
               | - Ga weg van de transfermarkt!            |
               | - Open Preview Pack / bekijk je Squad     |
               | - 2 minuten app even helemaal wegleggen   |
               +---------------------+---------------------+
                                     |
                                     +---> [ HERHAAL CYCLUS ]
```

---

### De 4 Regels voor Effectief & Veilig Snipen

#### 1. De 3-4 Seconden Regel (Pacing)
* **Het gevaar:** 10 keer per seconde op de zoekknop drukken triggert binnen 2 minuten een softban.
* **De veilige methode:** Houd een vast ritme aan van **1 zoekopdracht per 3 tot 4 seconden** (maximaal 15 tot 18 zoekopdrachten per minuut). 
* **Tip:** Verander bij *elke* zoekactie de **Minimale Biedprijs** met 1 tik omhoog of omlaag (bijv. 15.000 $\rightarrow$ 15.250 $\rightarrow$ 15.000). Dit voorkomt dat EA verouderde gecachte zoekresultaten terugstuurt én het simuleert een menselijke actie.

#### 2. Target Rotatie (Breek het patroon)
Blijf nooit 15 minuten achter elkaar op dezelfde speler zoeken. Stel **3 verschillende doelen** in en wissel na elke 3 à 4 minuten:
* **Target 1:** Populaire meta-kaart met fluctuaties (bijv. snipen onder marktprijs).
* **Target 2:** Populaire SBC-fodder (bijv. 84/85 rated spelers onder een vaste maximumprijs).
* **Target 3:** Positiewissels, chemistry styles of specifieke clubfilters.

#### 3. Direct Lijsten (Verwerk flow)
Zodra je een speler snipet:
1. Druk direct op **"Item aanbieden"**.
2. Zet hem direct te koop voor de actuele marktprijs met **1 uur** veilingduur.
3. *Waarom:* Dit onderbreekt je snipereeks automatisch voor ~10-15 seconden, wat je serverbelasting even laat zakken.

#### 4. De Verplichte Markt-Pauze (Cooldown)
Na **10 tot 12 minuten** actief snipen (ongeveer 150-180 zoekacties in totaal):
* Verlaat de transfermarkt volledig.
* Ga naar het **Store**-tabblad (bekijk je Preview Pack) of naar **Club/Squad**.
* Doe 2 tot 3 minuten **helemaal niets** op de markt. Dit reset de *"request-teller"* van het EA-algoritme.

---

### Samenvatting van de Limieten bij deze methode:
| Onderdeel | Veilig Maximum |
| :--- | :--- |
| **Zoekacties per minuut** | 15 – 18 |
| **Totale zoektijd per sessie** | 10 – 12 minuten achter elkaar |
| **Cooldown tussendoor** | 3 – 5 minuten |
| **Max. actieve veilingen** | 100 items (altijd via *Relist All*) |