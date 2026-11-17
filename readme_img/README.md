# Práctica 1.4 — HTTPS con certificado autofirmado en Apache

## Identificación

| | |
|---|---|
| **Alumno** | Roberto Sainz Arjona |
| **Módulo** | Despliegue de Aplicaciones Web (DAW2) – Curso 2026-2027 |
| **Actividad** | Actividad 2.2 – Práctica 1.4: HTTPS con certificado autofirmado en Apache |
| **Repositorio** | `rSainz21/practica2_02DAWRoberto` |
| **Fecha** | 13 y 16 de noviembre de 2026 |

### Datos del despliegue

| Elemento | Valor |
|---|---|
| Región | `us-east-1` (Norte de Virginia) |
| Instancia | `i-0e6bf214a504bb8db` |
| AMI | Ubuntu Server 26.04 LTS (`ami-0547ecbf0e9b4aeb5`, 64 bits x86) |
| Sistema | Ubuntu 26.04.1 LTS, kernel `7.0.0-1016-aws` |
| Tipo | `t3.micro` (apto para la capa gratuita) |
| Par de claves | `vockey` |
| IP privada | `172.31.18.228` |
| IP elástica | `52.3.52.227` |
| Dominio de pruebas | `practica-https.test` |

---

## Estructura del repositorio

```
.
├── README.md                              ← este documento
├── .gitignore                             ← excluye .env y claves privadas
├── conf
│   ├── 000-default.conf                   ← plantilla del virtual host HTTP (redirige a HTTPS)
│   └── practica-https-ssl.conf            ← plantilla del virtual host HTTPS
├── img                                    ← capturas de las evidencias
└── scripts
    ├── .env.example                       ← variables con valores de ejemplo
    ├── install_apache.sh                  ← instala Apache si no está instalado
    └── setup_selfsigned_certificate.sh    ← crea el certificado y configura HTTPS
```

Las plantillas de `conf/` no llevan escritos el dominio ni las rutas: llevan los marcadores `__DOMAIN__`, `__CERT_CRT__` y `__CERT_KEY__`, que el script sustituye con `sed` por los valores del `.env`. Así el repositorio sirve para cualquier dominio sin tocar los `.conf`.

---

## Fundamentos

HTTPS es HTTP sobre TLS. Al conectarse, el servidor envía su certificado, que contiene su clave pública. El cliente usa esa clave para negociar el cifrado de la conexión y comprueba que el certificado corresponde al nombre al que se ha conectado.

En esta práctica el certificado es **autofirmado**: lo firma el propio servidor con su clave privada, en un solo paso, sin pasar por una autoridad de certificación (CA). El cifrado es igual de fuerte que con un certificado de una CA, pero el navegador no puede verificar quién lo emite y muestra un aviso. Por eso solo se usa en pruebas, entornos internos y docencia.

Tres ideas que condicionan cómo está hecha la práctica:

- **El aviso del navegador es normal.** Al aceptarlo, el navegador guarda una excepción para ese sitio, pero el certificado no pasa a ser de confianza.
- **El nombre se valida en el SAN, no en el CN.** Chrome y Firefox ignoran el *Common Name*; por eso el certificado lleva el dominio y la IP elástica en la extensión `subjectAltName`.
- **La clave privada no sale del servidor.** Se guarda en `/etc/ssl/private/` con permisos `600`, y el `.gitignore` impide subir cualquier `*.key` o el `.env`.

---

## Pasos realizados

### Paso 1. Crear la instancia EC2

Desde AWS Academy → Learner Lab → *Start Lab* → *AWS*, entré en EC2 → *Launch instance* y lancé una instancia nueva con esta configuración:

- **AMI:** Ubuntu Server 26.04 LTS de la sección *Quick Start* (`ami-0547ecbf0e9b4aeb5`, 64 bits x86), que es la LTS más reciente y aparece como *Proveedor verificado*. El usuario por defecto de esta AMI es `ubuntu`.
- **Tipo de instancia:** `t3.micro` (2 vCPU, 1 GiB de memoria), apto para la capa gratuita.
- **Par de claves:** `vockey`, el par de AWS Academy (Paso 3).

Es una instancia recién creada, como pide el enunciado para las comprobaciones 1 y 2: así se ve la instalación completa de Apache desde cero.

![Captura 01 – AMI Ubuntu 26.04 LTS, tipo t3.micro y par de claves vockey](img/01-instancia-ami-tipo-claves.png)

*Captura 01 – Configuración de la instancia: AMI, tipo y par de claves.*

### Paso 2. Configurar el Security Group

En las reglas de entrada del Security Group de la instancia permito tres puertos:

| Tipo | Protocolo | Puerto | Origen | Descripción |
|---|---|---|---|---|
| SSH | TCP | 22 | Mi IP (`213.96.236.200/32`) | Administración |
| HTTP | TCP | 80 | `0.0.0.0/0` (Anywhere-IPv4) | Recibir peticiones HTTP para redirigirlas |
| HTTPS | TCP | 443 | `0.0.0.0/0` (Anywhere-IPv4) | Servir el sitio cifrado |

- **SSH** solo desde mi IP pública: así nadie más puede intentar conectarse al puerto 22.
- **HTTP (80)** abierto a todos, aunque el sitio se sirva por HTTPS: si se cerrara, quien escriba `http://` en el navegador no recibiría la redirección y vería un error de conexión.
- **HTTPS (443)** abierto a todos, porque es por donde se sirve el sitio.

**[PENDIENTE: sustituir esta captura por la de las reglas ya guardadas (pestaña *Reglas de entrada* del Security Group). En esta, tomada mientras editaba, la regla HTTPS aún no tiene origen.]**

![Captura 02 – Reglas de entrada del Security Group](img/02-security-group.png)

*Captura 02 – Reglas de entrada: SSH desde mi IP, HTTP y HTTPS.*

### Paso 3. Par de claves `vockey` y conexión SSH

Uso el par de claves `vockey` de AWS Academy. Su clave privada se descarga desde el Learner Lab en *AWS Details* → *SSH key* → *Download PEM* (archivo `labsuser.pem`), y la guardé en el Escritorio de mi equipo.

```bash
cd ~/Escritorio
chmod 400 "labsuser.pem"
ssh -i "labsuser.pem" ubuntu@ec2-18-234-66-181.compute-1.amazonaws.com
```

- `chmod 400` deja la clave legible solo por mi usuario; si tiene más permisos, SSH la rechaza con `UNPROTECTED PRIVATE KEY FILE`.
- En la primera conexión SSH pregunta si confío en la huella del servidor (`yes`) y la guarda en `~/.ssh/known_hosts`.
- El mensaje de bienvenida confirma el sistema: **Ubuntu 26.04.1 LTS**.

Esta primera conexión la hice el 13 de noviembre con la IP pública que AWS asigna al arrancar (`18.234.66.181`), antes de crear la IP elástica.

![Captura 03 – Primera conexión SSH con la clave de vockey](img/03-ssh-vockey.png)

*Captura 03 – Conexión SSH a la instancia con `labsuser.pem`.*

### Paso 4. Crear y asociar la IP elástica

En EC2 → *Direcciones IP elásticas* → *Asignar la dirección IP elástica* obtuve la IP **52.3.52.227**. Después, con ella seleccionada, *Acciones* → *Asociar la dirección IP elástica*:

- **Tipo de recurso:** Instancia.
- **Instancia:** `i-0e6bf214a504bb8db`.
- **Dirección IP privada:** `172.31.18.228`, la IP privada principal de la instancia.

La IP pública normal cambia cada vez que la instancia se para y arranca. El certificado lleva la IP dentro del SAN y el archivo `hosts` de mi equipo apunta a ella, así que necesito una IP fija: si cambiara, habría que regenerar el certificado y editar el `hosts`.

Al asociar la IP elástica, AWS libera la IP pública anterior (`18.234.66.181`), así que a partir de aquí me conecto siempre con `52.3.52.227`.

![Captura 04 – Asociación de la IP elástica 52.3.52.227 a la instancia](img/04-asociar-ip-elastica.png)

*Captura 04 – Asociación de la IP elástica a la instancia y a su IP privada.*

### Paso 5. Clonar el repositorio en la instancia

Este paso tiene dos partes que se hacen en sitios distintos: subir los archivos a GitHub **desde mi equipo** y clonarlos **en la instancia**.

#### 5.1. Subir los archivos a GitHub (desde mi equipo)

Descomprimo los archivos de la práctica y compruebo que están todos, incluido el `.gitignore` (oculto, por eso uso `ls -la`), y que **no** hay ningún `.env`:

![Captura 05 – Archivos de la práctica en mi equipo](img/05-zip-descomprimido-pc.png)

*Captura 05 – Contenido de la carpeta en mi equipo: `conf`, `scripts`, `.gitignore` y `README.md`.*

Inicializo el repositorio con `git init`. Git avisa de que la rama inicial se llama `master`; más adelante la renombro a `main`.

![Captura 06 – git init](img/06-git-init.png)

*Captura 06 – Inicialización del repositorio local.*

Añado los archivos y, antes del commit, reviso con `git status` qué se va a subir: los 7 archivos de la estructura, y ni `scripts/.env` ni ninguna clave.

```bash
git add .
git status
git commit -m "Practica 2.2 o 1.4: https con certificado autofirmado en apache"
```

![Captura 07 – git add, git status y git commit](img/07-git-add-status-commit.png)

*Captura 07 – Archivos preparados y primer commit.*

Renombro la rama a `main`, enlazo el repositorio remoto de GitHub y subo. En el resumen del commit se ve que los dos scripts se guardan con modo `100755`, es decir, con permiso de ejecución.

```bash
git branch -M main
git remote add origin https://github.com/rSainz21/practica2_02DAWRoberto.git
git push -u origin main
```

![Captura 08 – git branch, git remote y git push](img/08-git-branch-remote-push.png)

*Captura 08 – Renombrado de la rama, enlace con el remoto y primer push.*

Para autenticarme, GitHub no acepta la contraseña de la cuenta: en *Password* hay que pegar un **token de acceso personal**. Creé un token *classic* con el permiso `repo`, que es el que permite escribir en el repositorio.

El primer push fue rechazado porque el repositorio de GitHub ya tenía un `README.md` creado al crearlo, que mi copia local no tenía. Como ese README no tenía nada útil, forcé la subida para que el contenido de GitHub quedara sustituido por el mío:

```bash
git push -u origin main --force
```

![Captura 09 – git push --force](img/09-git-push-force.png)

*Captura 09 – Subida forzada: `main -> main (forced update)`.*

#### 5.2. Clonar el repositorio y preparar el `.env` (en la instancia)

Me conecto a la instancia por SSH, ya con el nombre DNS de la IP elástica:

```bash
cd ~/Escritorio
ssh -i "labsuser.pem" ubuntu@ec2-52-3-52-227.compute-1.amazonaws.com
```

![Captura 10 – Conexión SSH con la IP elástica](img/10-ssh-ip-elastica.png)

*Captura 10 – Conexión SSH a través de la IP elástica (`ec2-52-3-52-227`).*

Clono el repositorio en la instancia y creo el `.env` real a partir del de ejemplo:

```bash
git clone https://github.com/rSainz21/practica2_02DAWRoberto.git
cd practica2_02DAWRoberto
pwd
cp scripts/.env.example scripts/.env
nano scripts/.env
```

![Captura 11 – git clone en la instancia](img/11-git-clone-instancia.png)

*Captura 11 – Clonado del repositorio en `/home/ubuntu/practica2_02DAWRoberto`.*

En `nano` cambio la IP de ejemplo por mi IP elástica y pongo mis datos en el sujeto del certificado. El nombre de la organización va entre comillas porque lleva espacios. Este `.env` solo existe en la instancia: el `.gitignore` impide subirlo.

![Captura 12 – scripts/.env con mis datos y la IP elástica](img/12-env-editado.png)

*Captura 12 – `.env` real: datos del sujeto, `DOMAIN=practica-https.test`, `ELASTIC_IP=52.3.52.227` y `CERT_DAYS=365`.*

### Paso 6. Script `install_apache.sh`

Antes de ejecutarlo, leí el script con `cat scripts/install_apache.sh`. Comprueba con `dpkg -s apache2` si Apache ya está instalado y, si lo está, termina sin hacer nada. Si no, instala Apache con `apt` sin preguntas y deja el servicio habilitado y en marcha. La explicación de cada parte está en [Explicación de los scripts](#explicación-de-los-scripts).

Lo ejecuto sobre la instancia recién creada:

```bash
sudo ./scripts/install_apache.sh
```

El script actualiza la lista de paquetes desde los repositorios de Ubuntu (`resolute` es el nombre en clave de Ubuntu 26.04) e instala Apache sin intervención:

![Captura 13 – Ejecución de install_apache.sh](img/13-install-apache.png)

*Captura 13 – Primera ejecución de `install_apache.sh`.*

Compruebo que el servicio está funcionando con `systemctl status apache2`: aparece `enabled` (arranca con el sistema) y `active (running)`, con el proceso principal `apache2` y sus procesos hijo.

![Captura 14 – systemctl status apache2](img/14-systemctl-status.png)

*Captura 14 – Apache `enabled` y `active (running)`.*

### Paso 7. Script `setup_selfsigned_certificate.sh`

Este script comprueba que Apache está instalado, lee las variables del `.env`, crea el certificado con `subjectAltName`, copia las plantillas de `conf/` sustituyendo el dominio, habilita `ssl`, `rewrite` y el sitio HTTPS, y solo reinicia Apache si `apache2ctl configtest` da el visto bueno.

```bash
sudo ./scripts/setup_selfsigned_certificate.sh
```

En la salida se ve:

- `Creando el certificado autofirmado para practica-https.test (52.3.52.227)`: el dominio y la IP leídos del `.env`.
- Una serie de puntos y signos `+`: es `openssl` buscando los números primos de la clave RSA de 2048 bits.
- `Copiando los virtual hosts a /etc/apache2/sites-available`: las plantillas con el dominio ya sustituido.
- `a2enmod` habilitando `ssl` y sus dependencias (`mime`, que ya estaba activo, y `socache_shmcb`, la caché de sesiones TLS).

![Captura 15 – Ejecución de setup_selfsigned_certificate.sh](img/15-setup-certificado.png)

*Captura 15 – Creación del certificado y habilitación de los módulos.*

**[PENDIENTE: la captura se corta antes del final. Añadir una captura o la salida de las últimas líneas: `Syntax OK` y `HTTPS configurado. Prueba: curl -kI https://practica-https.test`.]**

### Paso 8. Ejecutar los dos scripts en orden

El orden importa: `setup_selfsigned_certificate.sh` comprueba que Apache está instalado y, si no, se detiene pidiendo ejecutar antes `install_apache.sh`.

Después de la primera ejecución (pasos 6 y 7), vuelvo a lanzar los dos scripts en orden:

```bash
sudo ./scripts/install_apache.sh
sudo ./scripts/setup_selfsigned_certificate.sh
```

- `install_apache.sh` detecta que Apache ya está instalado, muestra `Apache ya está instalado.` y termina sin instalar nada. Es la **Comprobación 2**.
- `setup_selfsigned_certificate.sh` genera un certificado nuevo y, como los módulos y sitios ya estaban habilitados, `a2enmod` y `a2ensite` responden `already enabled`. Esto demuestra que los scripts se pueden reejecutar sin romper nada.

![Captura 16 – Reejecución de los dos scripts](img/16-reejecucion-scripts.png)

*Captura 16 – Reejecución: `Apache ya está instalado.` y módulos y sitios `already enabled`.*

### Paso 9. Resolver el dominio en mi equipo y acceder

`practica-https.test` no existe en DNS (el dominio `.test` está reservado para pruebas), así que lo resuelvo a mano en el archivo `hosts` de **mi equipo** (Linux), no en el de la instancia:

```bash
sudo nano /etc/hosts
```

Añado al final la línea:

```text
52.3.52.227    practica-https.test
```

Y compruebo que se resuelve:

```bash
getent hosts practica-https.test
```

**[PENDIENTE: captura de `/etc/hosts` y de `getent hosts practica-https.test` en mi equipo, con el prompt de mi PC visible.]**

Accesos desde el navegador:

| URL | Resultado esperado | Resultado obtenido |
|---|---|---|
| `http://practica-https.test` | Redirige a `https://practica-https.test/` y muestra el aviso de certificado | **[PENDIENTE]** |
| `https://practica-https.test` | Aviso de CA no confiable; tras aceptarlo, la página de Apache | **[PENDIENTE]** |
| `http://52.3.52.227` | Redirige a `https://52.3.52.227/` | **[PENDIENTE]** |
| `https://52.3.52.227` | Aviso de CA no confiable, pero **sin** error de nombre, porque la IP está en el SAN | **[PENDIENTE]** |

### Paso 10. Comprobaciones y evidencias

Ver el apartado [Verificación y evidencias](#verificación-y-evidencias).

### Paso 11. Detener la instancia y liberar la IP elástica

Al terminar: EC2 → *Instancias* → `i-0e6bf214a504bb8db` → *Estado de la instancia* → *Detener instancia*.

Si no voy a seguir usándola: EC2 → *Direcciones IP elásticas* → `52.3.52.227` → *Acciones* → *Desasociar la dirección IP elástica* y después *Liberar direcciones IP elásticas*. AWS cobra por hora cada IPv4 pública, y una IP elástica reservada sigue gastando crédito aunque la instancia esté parada.

**[PENDIENTE: indicar si se detuvo la instancia y si se liberó la IP, con captura del estado *Detenida*.]**

---

## Explicación de los scripts

### `scripts/install_apache.sh`

| Parte | Qué hace y por qué |
|---|---|
| `set -euo pipefail` | El script se detiene si falla un comando (`-e`), si se usa una variable sin definir (`-u`) o si falla cualquier comando de una tubería (`pipefail`). Evita seguir adelante tras un error. |
| `if [[ $EUID -ne 0 ]]` | Comprueba que se ejecuta como root (con `sudo`), porque instalar paquetes y gestionar servicios lo requiere. |
| `dpkg -s apache2 \| grep -q "Status: install ok installed"` | Consulta en la base de datos de paquetes si Apache está instalado. Si lo está, muestra `Apache ya está instalado.` y sale con `exit 0`. Se filtra la línea `Status` porque `dpkg -s` también devuelve éxito para un paquete desinstalado que conserva su configuración (`deinstall ok config-files`). |
| `export DEBIAN_FRONTEND=noninteractive` | `apt` no abre ningún diálogo de configuración: la instalación no necesita al usuario. |
| `export NEEDRESTART_MODE=a` | En Ubuntu, `needrestart` puede preguntar qué servicios reiniciar tras instalar; con `a` los reinicia sin preguntar. |
| `apt-get -o DPkg::Lock::Timeout=300 update -y` | Actualiza la lista de paquetes. En una instancia recién creada, `unattended-upgrades` suele tener `apt` bloqueado unos minutos; esta opción espera hasta 5 minutos en lugar de fallar. |
| `apt-get ... install -y apache2` | Instala Apache aceptando automáticamente (`-y`). Los módulos `ssl` y `rewrite` vienen en el paquete, solo falta habilitarlos. |
| `systemctl enable --now apache2` | `enable` hace que Apache arranque con el sistema y `--now` lo arranca ya. |
| `systemctl is-active` / `is-enabled` | Muestra al final `active` y `enabled` como confirmación. |

### `scripts/setup_selfsigned_certificate.sh`

| Parte | Qué hace y por qué |
|---|---|
| `SCRIPT_DIR=...`, `ENV_FILE`, `CONF_DIR` | Calcula las rutas del `.env` y de `conf/` a partir de dónde está el script, así funciona aunque se lance desde otra carpeta. |
| Comprobación de root | Igual que en el otro script: escribir en `/etc` y reiniciar Apache requiere `sudo`. |
| `dpkg -s apache2 ...` | Si Apache no está instalado, se detiene con el mensaje «Ejecuta antes: sudo ./scripts/install_apache.sh». |
| Comprobación de `.env` | Si no existe `scripts/.env`, se detiene e indica cómo crearlo a partir de `.env.example`. |
| `set -a; source "$ENV_FILE"; set +a` | Carga todas las variables del `.env`: datos del sujeto, dominio, IP elástica, días de validez y rutas. |
| Bucle `REQUIRED_VARS` | Recorre la lista de variables obligatorias y se detiene indicando cuál falta. `${!var}` lee el valor de la variable cuyo nombre está en `var`. |
| `openssl req -x509 -nodes -days ... -newkey rsa:2048` | Crea en un solo paso una clave RSA de 2048 bits y un certificado autofirmado (`-x509`), sin contraseña en la clave (`-nodes`) para que Apache arranque sin pedirla. |
| `-subj "/C=.../CN=$DOMAIN/..."` | Rellena los datos del sujeto desde el `.env`, evitando las preguntas interactivas de `openssl`. |
| `-addext "subjectAltName=DNS:$DOMAIN,IP:$ELASTIC_IP"` | Añade el dominio y la IP elástica en el SAN, que es lo que validan los navegadores. |
| `chown` / `chmod 600` / `chmod 644` | La clave privada solo la lee root; el certificado es público y puede leerlo cualquiera. |
| Bucle `cp` + `sed -i` | Copia las dos plantillas a `/etc/apache2/sites-available/` y sustituye `__DOMAIN__`, `__CERT_CRT__` y `__CERT_KEY__` por los valores del `.env`. Se usa `\|` como separador de `sed` porque las rutas contienen `/`. |
| `a2enmod ssl rewrite` | Habilita `mod_ssl` (HTTPS) y `mod_rewrite` (la redirección del puerto 80). |
| `a2ensite 000-default.conf practica-https-ssl.conf` | Habilita el sitio HTTPS (crea el enlace en `sites-enabled/`). `000-default` ya viene habilitado; incluirlo asegura que lo esté. |
| `if ! apache2ctl configtest` | Comprueba la sintaxis antes de reiniciar. Si falla, se detiene y Apache sigue funcionando con la configuración anterior, en lugar de quedarse caído. |
| `systemctl restart apache2` | Reinicia Apache para cargar los módulos nuevos (cargar un módulo requiere `restart`, no basta `reload`). |

Si se vuelve a ejecutar, el script genera un certificado nuevo y vuelve a copiar las plantillas, con el mismo resultado (Captura 16).

### Plantillas de `conf/`

**`000-default.conf`** (puerto 80): `RewriteRule ^ https://%{HTTP_HOST}%{REQUEST_URI} [L,R=301]` redirige cualquier URL (`^`) a la misma dirección con `https://`, conservando el host y la ruta. `R=301` es una redirección permanente y `L` detiene el procesado de reglas. No hace falta `RewriteCond %{HTTPS} off`, porque en el puerto 80 la conexión nunca es HTTPS.

**`practica-https-ssl.conf`** (puerto 443): `SSLEngine on` activa TLS en el virtual host, y `SSLCertificateFile` y `SSLCertificateKeyFile` apuntan al certificado y a la clave creados por el script. Tiene logs propios (`practica-https-error.log` y `practica-https-access.log`) para separar el tráfico HTTPS. Es un archivo propio, en vez de modificar `default-ssl.conf`.

### `.env.example` y `.gitignore`

`.env.example` documenta todas las variables con valores de ejemplo (la IP `203.0.113.10` es de un rango reservado para documentación). El `.env` real se crea copiándolo en la instancia (Captura 12). `.gitignore` excluye `.env`, `scripts/.env` y los ficheros de claves (`*.key`, `*.pem`, `*.csr`, `*.p12`, `*.pfx`), para que nunca se suban al repositorio aunque se haga `git add .`.

---

## Verificación y evidencias

Las comprobaciones 1 a 5 se hacen **en la instancia**. Las 6 a 9 se hacen **desde mi equipo**, porque solo mi `/etc/hosts` resuelve `practica-https.test` y así se comprueba también el Security Group.

| Nº | Comprobación | Resultado | Evidencia |
|---|---|---|---|
| 1 | Instalación de Apache | ✅ Instalado sin preguntas; `active (running)` y `enabled` | Capturas 13 y 14 |
| 2 | Reejecución del script de instalación | ✅ `Apache ya está instalado.` | Captura 16 |
| 3 | Sujeto, validez y SAN del certificado | **[PENDIENTE]** | — |
| 4 | Sintaxis de Apache | **[PENDIENTE]** | — |
| 5 | Puertos a la escucha | **[PENDIENTE]** | — |
| 6 | Redirección HTTP → HTTPS | **[PENDIENTE]** | — |
| 7 | Respuesta HTTPS | **[PENDIENTE]** | — |
| 8 | Negociación TLS | **[PENDIENTE]** | — |
| 9 | Navegador | **[PENDIENTE]** | — |

### Comprobación 1. Instalación de Apache

```bash
sudo ./scripts/install_apache.sh
systemctl status apache2
```

El script instala Apache sin ninguna pregunta, y `systemctl status` muestra el servicio habilitado y en marcha:

```text
● apache2.service - The Apache HTTP Server
     Loaded: loaded (/usr/lib/systemd/system/apache2.service; enabled; ...)
     Active: active (running) since Mon 2026-11-16 17:04:13 UTC; 29s ago
   Main PID: 2233 (apache2)
```

![Captura 13 – Ejecución de install_apache.sh](img/13-install-apache.png)

![Captura 14 – systemctl status apache2](img/14-systemctl-status.png)

### Comprobación 2. Reejecución del script de instalación

```bash
sudo ./scripts/install_apache.sh
```

```text
Apache ya está instalado.
```

El script detecta la instalación con `dpkg -s` y termina sin volver a instalar nada.

![Captura 16 – Reejecución de los scripts](img/16-reejecucion-scripts.png)

### Comprobación 3. Sujeto, validez y SAN del certificado

```bash
openssl x509 -in /etc/ssl/certs/apache-selfsigned.crt -noout -subject -dates -ext subjectAltName
```

**Esperado:** los datos del `.env` en el sujeto, 365 días entre `notBefore` y `notAfter`, y el dominio y la IP en el SAN:

```text
subject=C = ES, ST = Cantabria, L = Torrelavega, O = IES Miguel Herrero Pereda, OU = DAW2, CN = practica-https.test, emailAddress = ...
notBefore=Nov 16 ... 2026 GMT
notAfter=Nov 16 ... 2027 GMT
X509v3 Subject Alternative Name:
    DNS:practica-https.test, IP Address:52.3.52.227
```

**[PENDIENTE: ejecutar en la instancia y pegar la salida real o la captura.]**

### Comprobación 4. Sintaxis de Apache

```bash
sudo apache2ctl configtest
```

**Esperado:** `Syntax OK`.

**[PENDIENTE: pegar la salida o la captura.]**

Puede aparecer antes el aviso `AH00558: apache2: Could not reliably determine the server's fully qualified domain name`. No es un error: indica que no hay `ServerName` en la configuración global (solo en los virtual hosts) y no impide que Apache funcione.

### Comprobación 5. Puertos a la escucha

```bash
sudo ss -tlnp | grep apache2
```

**Esperado:** dos líneas `LISTEN`, una en `*:80` y otra en `*:443`, del proceso `apache2`.

**[PENDIENTE: pegar la salida o la captura.]**

### Comprobación 6. Redirección HTTP → HTTPS (desde mi equipo)

```bash
curl -I http://practica-https.test
```

**Esperado:** `HTTP/1.1 301 Moved Permanently` y la cabecera `Location: https://practica-https.test/`.

**[PENDIENTE: pegar la salida o la captura, ejecutado desde mi PC.]**

### Comprobación 7. Respuesta HTTPS (desde mi equipo)

```bash
curl -kI https://practica-https.test
```

**Esperado:** `HTTP/1.1 200 OK`. La opción `-k` hace que `curl` acepte el certificado aunque no sea de confianza; sin ella fallaría con `SSL certificate problem: self-signed certificate`.

**[PENDIENTE: pegar la salida o la captura, ejecutado desde mi PC.]**

### Comprobación 8. Negociación TLS (desde mi equipo)

```bash
openssl s_client -connect practica-https.test:443 -servername practica-https.test < /dev/null
```

**Esperado:** en la salida hay que localizar:

- **Certificado presentado:** en `Certificate chain`, el sujeto (`s:`) y el emisor (`i:`) son el mismo, porque es autofirmado.
- **Versión TLS y cifrado:** una línea como `New, TLSv1.3, Cipher is TLS_AES_256_GCM_SHA384`.
- **Verificación:** `Verify return code: 18 (self-signed certificate)`, que confirma que el cifrado funciona pero el certificado no está firmado por una CA de confianza.

`< /dev/null` cierra la entrada para que `s_client` termine en lugar de quedarse esperando.

**[PENDIENTE: pegar la salida o la captura, e indicar la versión TLS y el cifrado obtenidos.]**

### Comprobación 9. Navegador

Acceso a `https://practica-https.test` desde el navegador de mi equipo.

**Esperado:** aviso de CA no confiable (en Firefox, «Advertencia: riesgo potencial de seguridad» con `SEC_ERROR_UNKNOWN_ISSUER`; en Chrome, «La conexión no es privada» con `NET::ERR_CERT_AUTHORITY_INVALID`). Tras aceptar el riesgo, se ve la página de Apache. En los detalles del certificado (clic en el icono a la izquierda de la URL → certificado), el emisor y el sujeto coinciden, y en *Nombre alternativo del sujeto* aparecen el dominio y la IP.

**[PENDIENTE: tres capturas: el aviso de seguridad, la página tras aceptarlo y los detalles del certificado.]**

---

## Incidencias y resolución

| Incidencia | Causa | Solución |
|---|---|---|
| El primer `git push` fue rechazado (`rejected ... fetch first`) | Al crear el repositorio en GitHub se generó un `README.md` que no estaba en mi copia local | Como ese README no tenía nada útil, subí con `git push -u origin main --force` para sustituirlo por el mío (Captura 09) |
| `git push` devolvía `403 Permission denied` | El token de GitHub no tenía permiso de escritura en el repositorio | Creé un token *classic* con el permiso `repo` y lo usé como contraseña |
| Git creó la rama `master` en vez de `main` | Es el nombre por defecto de mi versión de Git | `git branch -M main` antes del push (Capturas 06 y 08) |
| Ejecuté `chmod` sobre `labsuser.pem` y `git init` dentro de la instancia | Confundí la terminal de la instancia (`ubuntu@ip-172-31-18-228`) con la de mi equipo | Borré el repositorio creado por error con `rm -rf ~/.git`. La clave y la subida a GitHub se hacen en mi equipo; el clonado y los scripts, en la instancia |
| La IP de la primera conexión SSH dejó de servir | Al asociar la IP elástica, AWS libera la IP pública anterior (`18.234.66.181`) | Me conecto con la IP elástica (Captura 10) |
| **[PENDIENTE: confirmar]** Añadí el dominio al `/etc/hosts` de la instancia en vez de en el de mi equipo | Misma confusión entre las dos terminales | La línea `52.3.52.227 practica-https.test` va en el `/etc/hosts` de mi PC, que es desde donde se hacen las comprobaciones 6 a 9 |

---

## Conclusiones

- Automatizar el despliegue con scripts permite repetirlo en una instancia nueva sin pasos manuales ni errores de copia. Además, comprobar el estado antes de actuar (`dpkg -s`, `apache2ctl configtest`) hace que los scripts se puedan reejecutar sin romper nada, como se ve en la Captura 16.
- Separar la configuración (`.env`) del código (scripts y plantillas) permite publicar el repositorio sin exponer la IP, los datos personales ni la clave privada. Con el `.gitignore` y revisando `git status` antes de cada commit, me aseguré de que ni el `.env` ni la clave llegaran a GitHub.
- La IP elástica es necesaria cuando la IP forma parte de la configuración: si cambiara, el certificado y el `hosts` dejarían de ser válidos.
- El certificado autofirmado cifra igual que uno de una CA, pero no demuestra la identidad del servidor ante el navegador. Para un sitio público habría que usar una CA, por ejemplo Let's Encrypt.
- Lo que más me costó fue distinguir en qué máquina tenía que hacer cada cosa (mi equipo o la instancia) y la autenticación de GitHub con token. **[PENDIENTE: revisar y adaptar con tus palabras.]**

---

## Fuentes

- Apache HTTP Server 2.4 – `mod_ssl`: https://httpd.apache.org/docs/2.4/mod/mod_ssl.html
- Apache HTTP Server 2.4 – `mod_rewrite`: https://httpd.apache.org/docs/2.4/mod/mod_rewrite.html
- OpenSSL – `openssl-req`: https://docs.openssl.org/3.0/man1/openssl-req/
- AWS – Direcciones IP elásticas: https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/elastic-ip-addresses-eip.html
- GitHub – Tokens de acceso personal: https://docs.github.com/es/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens
- RFC 6761 – Nombres de dominio de uso especial (`.test`): https://www.rfc-editor.org/rfc/rfc6761
- Enunciado de la Actividad 2.2 (Práctica 1.4), DAW2, curso 2026-2027.
