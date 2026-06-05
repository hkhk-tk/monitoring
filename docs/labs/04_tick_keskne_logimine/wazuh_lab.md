# Päev 4 (pärastlõuna): Wazuh SIEM — agent, tuvastus, Active Response

**Kestus:** ~1.5 tundi (klassis)
**Tase:** kesktase
**Eeldused:** Päev 3 (OpenSearch — Wazuhi indexer *on* OpenSearch). SSH, Linux CLI, sudo. Loe enne [Päev 4 loeng](../../materials/lectures/paev4-loeng.md) SIEM + Wazuh osa.
**VM:** sinu VM (`ssh <eesnimi>@192.168.35.12X` / `192.168.100.12X`)

---

## Miks see labor

Päev 2 panid Zabbixi agendid saatma andmeid kesksele serverile. Päev 3 ehitasid OpenSearchi klastri. **SIEM ühendab need kaks ideed turbe vaates:** kerged agendid igal masinal saadavad turbesündmused (logid, failimuutused, sisselogimised) kesksele **managerile**, mis rakendab tuvastusreegleid ja hoiab andmeid OpenSearchis. Wazuh on selle avatud lähtekoodiga standard.

Erinevalt hommikusest TICK-labist **ei ehita sa tervet stacki** — manager + indexer + dashboard jookseb juba keskselt (`192.168.100.120`). Sina paned oma VM-ile kerge **agendi** (~0.1 GB RAM), enrollid ta managerisse ja vaatad, kuidas su masina sündmused jõuavad ühisesse dashboardi. See on päris SIEM-arhitektuur: hajutatud agendid → keskne analüüs.

!!! info "Mida sa teed ja kontrollid"
    **Teed:** 1) paigaldad wazuh-agendi, 2) enrollid kesksesse managerisse, 3) tekitad turbesündmuse (ebaõnnestunud sisselogimised), 4) leiad alerti dashboardist.<br>
    **Kontrollid:** agent on dashboardis **Active**; sinu ebaõnnestunud login'id ilmuvad alertina (reegel **5710**).<br>
    **Allalaadimine on väike** — agent on üks pakk (~kümneid MB), mitte raske stack nagu hommikune InfluxDB. Sekundid, mitte minutid.

---

## 🎯 Õpiväljundid

**Teadmised:**

1. Kirjeldab Wazuhi nelja komponenti (agent, manager, indexer, dashboard) ja kummagi rolli.
2. Selgitab, miks SIEM kasutab keskset managerit, mitte iga masina lokaalset analüüsi.

**Oskused:**

3. Paigaldab ja enrollib Wazuhi agendi kesksesse managerisse.
4. Tekitab turbesündmuse (ebaõnnestunud sisselogimised) ja leiab vastava alerti dashboardist.
5. Tõlgendab alerti: reegli ID, tase, allikas.

---

## Eeltöö

Agent on kerge — muud stack'id ei sega. Kui hommikune TICK veel jookseb ja tahad mälu vabaks: `cd ~/paev4 && docker compose down`.

!!! warning "Kui `yum`/`dnf` jääb toppama"
    Sama IPv6-probleem mis docker pull. Lülita välja:
    ```bash
    sudo sysctl -w net.ipv6.conf.all.disable_ipv6=1 net.ipv6.conf.default.disable_ipv6=1
    ```

---

## Osa 1 · Paigalda ja enrolli agent

> **Miks:** agent on programm, mis su masinal kogub turbesündmusi ja saadab managerile. Alates Wazuh 4.0-st piisab enrollimiseks **ühest asjast** — manageri IP-st installi ajal. Agent küsib ise võtme ja registreerub; käsitsi võtmevahetust pole vaja.

### 1.1 Lisa Wazuhi pakihoidla

```bash
sudo rpm --import https://packages.wazuh.com/key/GPG-KEY-WAZUH
sudo tee /etc/yum.repos.d/wazuh.repo > /dev/null << 'EOF'
[wazuh]
gpgcheck=1
gpgkey=https://packages.wazuh.com/key/GPG-KEY-WAZUH
enabled=1
name=EL-$releasever - Wazuh
baseurl=https://packages.wazuh.com/4.x/yum/
protect=1
EOF
```

### 1.2 Paigalda agent, suunatud kesksele managerile

`WAZUH_MANAGER` ütleb agendile, kuhu enrollida. Meie keskne manager on `192.168.100.120`:

```bash
sudo WAZUH_MANAGER="192.168.100.120" yum install -y wazuh-agent
```

See kirjutab manageri IP automaatselt `/var/ossec/etc/ossec.conf`-i `<client><server>` alla.

### 1.3 Käivita ja keela auto-uuendus

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now wazuh-agent
# väldi tahtmatut uuendust üle manageri versiooni:
sudo sed -i "s/^enabled=1/enabled=0/" /etc/yum.repos.d/wazuh.repo
```

### 1.4 Kontrolli ühendust

```bash
sudo systemctl status wazuh-agent --no-pager
sudo tail -15 /var/ossec/logs/ossec.log
```

Otsi logist rida nagu `Connected to the server` ja `Agent is now ...`. Kui näed seda, oled managerisse enrollitud.

!!! tip "Kui logis on `Unable to connect` / `Connection refused`"
    Kontrolli, et manageri IP on õige (`grep -A2 '<server>' /var/ossec/etc/ossec.conf` peab näitama `192.168.100.120`) ja et oled VPN/klassivõrgus, kust `192.168.100.120` on kättesaadav. Pordid 1514 (side) ja 1515 (enroll) peavad olema avatud.

    **Pane tähele:** sinu agendi `ossec.conf`-is on mainitud ainult port **1514** — see on normaalne. Port **1515** (enrollimine) elab **manageri** poolel, mitte agendi konfis. Agent kasutab 1515 vaid installihetkel võtme küsimiseks; pärast seda käib kogu side üle 1514.

💭 **Mõtle:** sa ei vahetanud käsitsi ühtegi võtit. Mis julgeolekurisk on sellega, et agent enrollib end automaatselt ilma paroolita? Millal tootmises paneksid enrollimisele parooli (`WAZUH_REGISTRATION_PASSWORD`)?

---

## Osa 2 · Leia end dashboardist

> **Miks:** manager näitab kõiki enrollitud agente ühes kohas — see on SIEM-i väärtus: üks vaade kõigile masinatele.

Ava brauserist **`https://192.168.100.120`** (iseallkirjastatud sert → nõustu hoiatusega). Logi sisse:

- Kasutaja: `admin`
- Parool: `SecretPassword`

Mine **Agents** (või Server management → Endpoints summary). Leia oma VM nimi nimekirjast — staatus **Active** (roheline). Kõik klassi agendid on samas nimekirjas.

💭 **Mõtle:** kõigi õpilaste masinad on ühes nimekirjas. Mis vahe on sellel ja Päev 2 Zabbixil, kus iga host oli samuti keskses serveris? Mille poolest erineb turbe-keskne vaade (Wazuh) jõudlus-kesksest (Zabbix)?

---

## Osa 3 · Tekita tuvastus — ebaõnnestunud sisselogimised

> **Miks:** SIEM-i mõte on **tuvastada**, mitte ainult koguda. Üks levinuim signaal on korduvad ebaõnnestunud sisselogimised (brute-force katse). Wazuhil on selle jaoks vaikereeglid — tekitame sündmuse ja vaatame, kuidas reegel rakendub.

Tekita oma VM-il viis ebaõnnestunud SSH-sisselogimist olematu kasutajaga:

```bash
for i in 1 2 3 4 5; do
  ssh -o StrictHostKeyChecking=no -o ConnectTimeout=3 olematukasutaja@127.0.0.1 true 2>/dev/null
done
```

Iga katse läheb `/var/log/secure`-i; agent loeb selle ja saadab managerile.

Dashboardis mine **Threat Hunting / Security Events** (või Discover), vali oma agent ja vaata viimaseid sündmusi. Otsi alerteid nagu:

- **5710** — *Attempt to login using a non-existent user* (tase 5)
- **5712** — *sshd: brute force trying to get access* (tase 10), kui katseid on piisavalt tihedalt

Klõpsa ühel alertil ja vaata välju: **rule.id**, **rule.level**, **rule.description**, **agent.name**, **data.srcip**.

!!! tip "Kui alerteid kohe ei näe"
    Andmete jõudmine võtab kuni ~30 s. Kontrolli, et ülal paremal on ajavahemik "Last 15 minutes" ja et valitud on õige agent. Värskenda lehte.

💭 **Mõtle:** reegel 5710 on tase 5, brute-force 5712 on tase 10. Miks on sama tüüpi sündmus (login fail) eri tasemega sõltuvalt kontekstist? Kuidas aitab tasemepõhine eskaleerimine SOC-meeskonnal prioritiseerida?

---

## Osa 4 · Active Response (valikuline, kodus)

> **Miks:** SIEM ei pea ainult teatama — ta saab **reageerida**. Wazuhi Active Response saab käivitada skripti, kui reegel rakendub: nt blokeerida ründav IP tulemüüris. See on automaatne kaitse, mis töötab ka öösel kui keegi ei vaata.

Wazuhi vaikekonfiguratsioonis on Active Response `firewall-drop`, mis blokeerib IP, mis ületab brute-force läve. Loe konfiguratsiooni (manageris):

```bash
# managerile pääseb keskselt; kohalik vaade agendi poolelt:
grep -A5 'active-response' /var/ossec/etc/ossec.conf
```

Mõtle läbi: kui agent tuvastab 8 ebaõnnestunud katset 120 s jooksul samalt IP-lt, käivitab manager `firewall-drop` selle agendi peal. Loengus nägid, miks automaatne reageerimine on kahe teraga mõõk (vale-positiivne → blokeerid iseennast).

💭 **Mõtle:** mis juhtuks, kui Active Response blokeeriks IP-d liiga agressiivselt? Too näide olukorrast, kus automaatne blokeerimine teeks rohkem kahju kui kasu.

---

## ✅ Lõpukontroll (enesekontroll, verifitseeritav)

**Tehniline:**

- [ ] `sudo systemctl status wazuh-agent` → `active (running)`.
- [ ] `/var/ossec/logs/ossec.log` sisaldab rida `Connected to the server`.
- [ ] Dashboardis (`https://192.168.100.120`) on sinu VM **Active** olekus.
- [ ] Pärast 5 ebaõnnestunud sisselogimist näed dashboardis reegli **5710** alerteid oma agendilt.
- [ ] Oskad ühel alertil nimetada `rule.id`, `rule.level`, `agent.name`.

**Arusaamine (vasta peast):**

- [ ] Nimetad Wazuhi neli komponenti ja kummagi rolli.
- [ ] Selgitad, miks indexer on OpenSearch (meenuta Päev 3) ja mis seal hoitakse.
- [ ] Selgitad, miks SIEM analüüsib keskselt, mitte igal masinal eraldi.

---

## Veaotsing

| Probleem | Kontroll | Lahendus |
|---|---|---|
| `yum install` jääb toppama | — | IPv6 välja (vt Eeltöö), proovi uuesti. |
| Agent `Unable to connect` | `grep -A2 '<server>' /var/ossec/etc/ossec.conf` | Manageri IP peab olema `192.168.100.120`; pead olema võrgus, kust see on ligi. |
| Agent paigaldatud, aga dashboardis pole | `sudo systemctl status wazuh-agent` | Käivita: `sudo systemctl enable --now wazuh-agent`. Oota ~30 s. |
| Dashboard ei avane | brauser | `https://` (mitte http), nõustu iseallkirjastatud serdiga. |
| Sisselogimine ebaõnnestub | — | `admin` / `SecretPassword` (väiketähed loevad). |
| Alerteid ei näe | ajavahemik UI-s | Sea "Last 15 minutes", vali õige agent, värskenda. |

---

## 📚 Allikad

| Allikas | URL | Miks oluline |
|---|---|---|
| Wazuh agent — Linux | <https://documentation.wazuh.com/current/installation-guide/wazuh-agent/wazuh-agent-package-linux.html> | Agendi paigaldus ja enroll. |
| Wazuh agent enrollment | <https://documentation.wazuh.com/current/user-manual/agent-enrollment/index.html> | Kuidas auto-enroll töötab. |
| Wazuh ruleset | <https://documentation.wazuh.com/current/user-manual/ruleset/index.html> | Reeglid, tasemed, rule.id. |
| Active Response | <https://documentation.wazuh.com/current/user-manual/capabilities/active-response/index.html> | Automaatne reageerimine. |
| Wazuh Docker (manager) | <https://documentation.wazuh.com/current/deployment-options/docker/wazuh-container.html> | Keskse stacki taust. |

--8<-- "_snippets/abbr.md"
