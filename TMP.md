### Zmiany w architekturze i kodzie

* **Usunięte moduły (Całkowity brak w infrastrukturze):**
* Klaster Kubernetes (`aks.tf`).
* System monitorowania logów (`logging.tf`).


* **Zakomentowane zasoby (Wyłączone z wdrożenia):**
* Bazy danych MySQL i PostgreSQL wraz z ich konfiguracjami (`sql.tf`).
* Narzędzie Network Watcher oraz jego logi przepływu sieciowego (`networking.tf`).
* Punkty końcowe magazynu danych (`storage_endpoint`) w politykach alertów dla baz MSSQL (`mssql.tf` i `sql.tf`).


* **Modyfikacje parametrów (Obejścia limitów i konfliktów):**
* **App Service:** Zmiana planu z `Dynamic S1` na `Basic B1`. Wymuszenie protokołu TLS w wersji 1.2.
* **Maszyny Wirtualne:** Zmniejszenie rozmiaru instancji Linux i Windows z `Standard_F2` na `Standard_D2s_v3`.
* **Key Vault:** Zmiana mechanizmu pobierania ID użytkownika na zmienną `var.object_id` oraz dodanie szerokich uprawnień (`get`, `list`, `delete`, `purge`, `recover`), w tym omyłkowo zduplikowanych.
* **Bazy MSSQL:** Skrócenie nazw (np. z `securitystorageaccount...` na `secsa...`) i wymuszenie protokołu TLS 1.2 dla wszystkich 7 serwerów.
* **Zmienne i Provider:** Zablokowanie wersji providera Azure na `2.99.0`, dodanie zmiennej `object_id` oraz ustawienie domyślnego regionu na `swedencentral`.
* **Konfiguracja Git:** Dodanie pliku `terraform.tfvars` i plików `*.disabled` do wykluczeń `.gitignore`, a także podmiana instrukcji w `README.md` na Twój skrypt wdrożeniowy.



### Wpływ na testy bezpieczeństwa (Skanowanie)

Wprowadzone zmiany drastycznie modyfikują powierzchnię ataku, którą wykryje skaner bezpieczeństwa.

**Znikające podatności (Fałszywie negatywne z powodu braku zasobu)**
Usunięcie i zakomentowanie plików sprawia, że skaner w ogóle nie weźmie pod uwagę kilkudziesięciu zaplanowanych błędów. Z raportu całkowicie znikną następujące reguły:

* **Kubernetes:** `CKV_AZURE_4`, `CKV_AZURE_5`, `CKV_AZURE_6`, `CKV_AZURE_7`, `CKV_AZURE_8`, `CKV_AZURE_115`, `CKV_AZURE_116`, `CKV_AZURE_117`, `CKV_AZURE_141`.
* **Bazy MySQL/PostgreSQL:** `CKV_AZURE_28`, `CKV_AZURE_29`, `CKV_AZURE_30`, `CKV_AZURE_32`, `CKV_AZURE_53`, `CKV_AZURE_54`, `CKV_AZURE_68`, `CKV_AZURE_94`, `CKV_AZURE_102`, `CKV_AZURE_127`, `CKV_AZURE_128`, `CKV_AZURE_130`, `CKV_AZURE_147`.
* **Logowanie i Sieć:** `CKV_AZURE_12` (Network Watcher), `CKV_AZURE_37`, `CKV_AZURE_38` (Log Profile).

**Niechciana naprawa podatności (Środowisko stało się zbyt bezpieczne)**
Projekt TerraGoat z założenia ma być dziurawy. Poprzez aktualizację protokołów TLS w celu obejścia blokad Azure, przypadkowo naprawiłeś błędy, które skaner miał wykryć jako krytyczne:

* **`CKV_AZURE_15` (App Service):** Wymuszenie `min_tls_version = "1.2"` sprawi, że skaner uzna aplikację za bezpieczną pod kątem szyfrowania.
* **`CKV_AZURE_52` (MSSQL):** Dodanie `minimum_tls_version = "1.2"` do wszystkich 7 serwerów SQL naprawia zaplanowaną lukę kryptograficzną.

### Co wymaga dalszych poprawek

1. **Duplikaty w Key Vault:** W pliku `key_vault.tf` uprawnienia `"get", "list", "delete"` w sekcji `key_permissions` powtarzają się dwukrotnie. Należy usunąć dublujące się linijki, aby uniknąć błędów parsowania HCL przez Terraform.
2. **Konflikt TLS w magisterce:** Musisz podjąć decyzję biznesową dotyczącą protokołu TLS. Jeśli w pracy magisterskiej chcesz opisać luki wynikające z używania przestarzałych protokołów (TLS 1.0/1.1), musisz przywrócić stare wartości i znaleźć inny sposób na ominięcie blokad polityk Azure (np. zignorowanie błędu wdrożenia dla tego konkretnego zasobu), albo wprost opisać w pracy, że chmura wymusiła na Tobie załatanie tych dwóch konkretnych podatności przed wdrożeniem.
3. **Polityki alertów MSSQL:** Zakomentowanie `storage_endpoint` i `storage_account_access_key` w politykach alertów (np. `azurerm_mssql_server_security_alert_policy.alertpolicy1`) odcina bazę od miejsca zapisu logów. Może to spowodować błąd wdrożenia samego Terraform (brak wymaganych parametrów dla polityki) lub fałszować wyniki testów dla reguł `CKV_AZURE_25`, `CKV_AZURE_26` i `CKV_AZURE_27`.

```sh
az sql server show \
  --resource-group "terragoat-dev" \
  --name "mssql2-dev4644" \
  --query "minimalTlsVersion" \
  -o tsv
```

## co sie dzialo

### `mssql.tf`

#### minimum tls | CKV_AZURE_52

**Chmura nie pozwala na obnizenie, utworzenie resource z TLS nizszym niz 1.2**

trzeba zostawic to pole bo pozniej terraform provider swiruje i nie pozwala na autodestroy

by default mssql server ma:
```
minimum_tls_version          = "1.2"
```

Azure od pewnego czasu globalnie wymusza odrzucanie żądań obniżenia TLS do wersji 1.0/1.1 dla nowo konfigurowanych zasobów PaaS. Dodatkowo sam provider Terraform traktuje wykasowanie tej linijki jako próbę ustawienia wartości null, co w przypadku tego konkretnego zasobu jest zablokowane regułą: cannot be removed once set.

i nie pozwala pozniej zmienic w terrafirmie wiec ustawilem na sztywno

Jeśli skaner IaC (np. Checkov) ma wykrywać CKV_AZURE_52 na poziomie kodu:

    Badanie statyczne kodu (SAST): skaner sprawdza plik .tf w repozytorium. Jeśli nie ma tam minimum_tls_version = "1.2", skaner zaliczy podatność, nawet jeśli w samej chmurze tego nie wdrożysz.

    Wdrożenie na żywo: Azure nie pozwoli na utworzenie lub zniżenie serwera do TLS 1.1 w nowszych wersjach API. Z punktu widzenia pracy dyplomowej jest to świetny przypadek do opisania: mechanizmy platformy chmurowej uniemożliwiające wdrożenie podatnego kodu IaC.

### `logging.tf`

```sh
az monitor log-profiles show --name "terragoat-dev"
az monitor log-profiles list --output table
az monitor log-profiles delete --name "terragoat-dev"
```
wygląda jakby coś się nie usunęło po poprzednim deploy ale juz wygląda legit

### `sql.tf`

Zakomentowane linijki (storage_endpoint i storage_account_access_key) mówią jedynie: „gdzie na dysku zapisać plik z logami”. Skanera w tych trzech regułach w ogóle to nie interesuje. Interesuje to tylko samo Azure podczas terraform apply. Zostawiając je zakomentowane, zadowalasz Azure, a Checkov i tak wystawi dokładnie te same mandaty.

single server mysql - retired:
https://techcommunity.microsoft.com/blog/adformysql/azure-database-for-mysql---single-server-retirement---key-updates-and-migration-/4055198

single server postgres - retired:
https://techcommunity.microsoft.com/blog/adforpostgresql/retiring-azure-postgresql-single-server-in-march-2025/3783783

#### deprecated

```
    203: "CKV_AZURE_127: wycofane API MySQL Single Server",
    204: "CKV_AZURE_94: wycofane API MySQL Single Server",
    205: "CKV_AZURE_53: wycofane API MySQL Single Server",
    206: "CKV_AZURE_54: wycofane API MySQL Single Server",
    207: "CKV_AZURE_28: wycofane API MySQL Single Server",
    208: "CKV_AZURE_147: wycofane API PostgreSQL Single Server",
    209: "CKV_AZURE_130: wycofane API PostgreSQL Single Server",
    210: "CKV_AZURE_29: wycofane API PostgreSQL Single Server",
    211: "CKV_AZURE_128: wycofane API PostgreSQL Single Server",
    212: "CKV_AZURE_102: wycofane API PostgreSQL Single Server",
    213: "CKV_AZURE_68: wycofane API PostgreSQL Single Server",
    214: "CKV_AZURE_32: wycofane API PostgreSQL Single Server",
    215: "CKV_AZURE_30: wycofane API PostgreSQL Single Server",
```

### `storage.tf`

Jeśli dopiszesz "AzureServices" do bypass w azurerm_storage_account_network_rules.test:

    Wiersz 222 (CKV_AZURE_36) przestanie być podatnością (zmieni status z FAIL na PASS).

    Jeśli Twój benchmark zakłada badanie podatności wyjściowych TerraGoat, wiersz 222 wypadnie z listy wykrytych problemów.


### `aks.tf`

```sh
az provider register --namespace Microsoft.ContainerService
az provider show -n Microsoft.ContainerService --query "registrationState" -o tsv
az policy assignment list --query "[?parameters.listOfAllowedLocations].parameters.listOfAllowedLocations.value[]" -o tsv | sort -u
```

Łącznie niemożliwe do fizycznego wdrożenia przez starzenie się chmury (Cloud Drift): 22 reguły z 133 (16,54%), natomiast 111 reguł (83,46%) przechodzi wdrożenie 1:1.

---

```py
DEPRECATED_IN_AZURE_API = {
    # AKS (Wiersze 113-121) - wygaszone API 2022-01-02-preview w providerze 2.99.0 + wycofany kube_dashboard / brak RBAC
    113: "CKV_AZURE_116: AKS - wycofane API 2022-01-02-preview",
    114: "CKV_AZURE_8: AKS - wycofane API 2022-01-02-preview (oraz usunięty kube_dashboard w Azure)",
    115: "CKV_AZURE_4: AKS - wycofane API 2022-01-02-preview",
    116: "CKV_AZURE_117: AKS - wycofane API 2022-01-02-preview",
    117: "CKV_AZURE_115: AKS - wycofane API 2022-01-02-preview",
    118: "CKV_AZURE_141: AKS - wycofane API 2022-01-02-preview",
    119: "CKV_AZURE_7: AKS - wycofane API 2022-01-02-preview",
    120: "CKV_AZURE_6: AKS - wycofane API 2022-01-02-preview",
    121: "CKV_AZURE_5: AKS - wycofane API 2022-01-02-preview (oraz wymóg RBAC w Azure)",

    # Bazy Single Server (Wiersze 203-215) - wycofana architektura Single Server
    203: "CKV_AZURE_127: wycofane API MySQL Single Server",
    204: "CKV_AZURE_94: wycofane API MySQL Single Server",
    205: "CKV_AZURE_53: wycofane API MySQL Single Server",
    206: "CKV_AZURE_54: wycofane API MySQL Single Server",
    207: "CKV_AZURE_28: wycofane API MySQL Single Server",
    208: "CKV_AZURE_147: wycofane API PostgreSQL Single Server",
    209: "CKV_AZURE_130: wycofane API PostgreSQL Single Server",
    210: "CKV_AZURE_29: wycofane API PostgreSQL Single Server",
    211: "CKV_AZURE_128: wycofane API PostgreSQL Single Server",
    212: "CKV_AZURE_102: wycofane API PostgreSQL Single Server",
    213: "CKV_AZURE_68: wycofane API PostgreSQL Single Server",
    214: "CKV_AZURE_32: wycofane API PostgreSQL Single Server",
    215: "CKV_AZURE_30: wycofane API PostgreSQL Single Server",
}
```


## any ideas pod nieobsluzone wyjatki

Podejście statyczne (bez deployu tych baz):
Jeśli robisz skan Checkovem z poziomu konsoli (checkov -d .), nie musisz robić terraform apply. Checkov analizuje sam tekst plików. Możesz odkomentować te bazy na czas skanu Checkovem (wtedy wykryje kompletne 133 podatności), a zakomentować je wyłącznie wtedy, gdy faktycznie stawiasz infrastrukturę na żywym Azure komendą apply.

*„Benchmark TerraGoat z 2020 roku w ~9,8% opiera się na zasobach Azure Single Server, które w latach 2024–2025 zostały trwale wycofane przez Microsoft, uniemożliwiając ich fizyczną alokację na współczesnej chmurze.”*

Do wykonania terraform apply na żywym Azure:
Musisz wyłączyć ten plik (np. zmienić nazwę z powrotem na aks.tf.disabled), tak jak wcześniej wyłączyłeś MySQL i PostgreSQL Single Server.

Do skanowania narzędziami SAST (Checkov) / spójności tabeli:
Na moment puszczania skanera zmieniasz nazwę z powrotem na aks.tf (skaner czyta tylko tekst z dysku, nie łączy się z API Azure, więc wykryje wszystkie 9 reguł z wierszy 113–121).

W tabeli i tekście pracy magisterskiej:
Dopisujesz wiersze 113–121 (9 reguł AKS) do tej samej kategorii, co bazy Single Server (wiersze 203–215).
