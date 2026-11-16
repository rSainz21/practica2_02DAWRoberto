# Práctica 1.4 — HTTPS con certificado autofirmado en Apache

## Identificación

| | |
|---|---|
| **Alumno** | Roberto Sainz Arjona |
| **Módulo** | Despliegue de Aplicaciones Web (DAW2) – Curso 2026-2027 |
| **Actividad** | Actividad 2.2 – Práctica 1.4: HTTPS con certificado autofirmado en Apache |
| **Repositorio** | `practica-01-04` |
| **Fecha** | **[COMPLETAR: fecha de realización]** |

> **Cómo usar este borrador.** Los apartados siguen la numeración del enunciado: **Paso 1 a Paso 11** son las *Tareas a realizar* y **Comprobación 1 a 9** es la tabla de *Verificación y evidencias*. En cada paso tienes dónde hacerlo, los comandos exactos, qué debes ver y qué captura hacer (📷). Lo marcado como **[COMPLETAR]** depende de tu instancia real (IP, versiones, salidas, incidencias). Antes de entregar, **borra este recuadro, los textos «Dónde:» y los corchetes**.
>
> **Evidencias:** el enunciado admite «la salida o una captura». Para las comprobaciones de terminal (1 a 8) pega la **salida como texto** en los bloques preparados. Para las capturas de la consola de AWS y del navegador, guarda las imágenes en una carpeta `img/` y se enlazan como `![texto](img/nombre.png)`.

---

## Estructura del repositorio

```
.
├── README.md                              ← este documento
├── .gitignore                             ← excluye .env y claves privadas
├── conf
│   ├── 000-default.conf                   ← plantilla del virtual host HTTP (redirige a HTTPS)
│   └── practica-https-ssl.conf            ← plantilla del virtual host HTTPS
└── scripts
    ├── .env.example                       ← variables con valores de ejemplo
    ├── install_apache.sh                  ← instala Apache si no está instalado
    └── setup_selfsigned_certificate.sh    ← crea el certificado y configura HTTPS
```

Las plantillas de `conf/` no llevan el dominio ni las rutas escritas: llevan los marcadores `__DOMAIN__`, `__CERT_CRT__` y `__CERT_KEY__`, que el script sustituye con `sed` por los valores del `.env`. Así el repositorio sirve para cualquier dominio sin tocar los `.conf`.

---

## Fundamentos

HTTPS es HTTP sobre TLS. Al conectarse, el servidor envía su certificado, que contiene su clave pública. El cliente usa esa clave para negociar el cifrado de la conexión y comprueba que el certificado corresponde al nombre al que se ha conectado.

En esta práctica el certificado es **autofirmado**: lo firma el propio servidor con su clave privada, en un solo paso, sin pasar por una autoridad de certificación (CA). El cifrado es igual de fuerte que con un certificado de una CA, pero el navegador no puede verificar quién lo emite y muestra un aviso. Por eso solo se usa en pruebas, entornos internos y docencia.

Tres ideas que condicionan cómo está hecha la práctica:

- **El aviso del navegador es normal.** Al aceptarlo, el navegador guarda una excepción para ese sitio, pero el certificado no pasa a ser de confianza.
- **El nombre se valida en el SAN, no en el CN.** Chrome y Firefox ignoran el *Common Name*; por eso el certificado lleva el dominio y la IP elástica en la extensión `subjectAltName`.
- **La clave privada no sale del servidor.** Se guarda en `/etc/ssl/private/` con permisos `600` y el `.gitignore` impide subir cualquier `*.key` o el `.env`.

---

## Pasos realizados

### Paso 1. Crear la instancia EC2

**Dónde:** AWS Academy → Learner Lab → *Start Lab* → cuando el punto esté en verde, *AWS* → EC2 → *Launch instance*.

| Parámetro | Valor |
|---|---|
| Nombre | `https-RSA` |
| AMI | Ubuntu Server LTS de *Quick Start* – **[COMPLETAR: versión exacta, p. ej. Ubuntu Server 24.04 LTS]** |
| Tipo de instancia | **[COMPLETAR: t2.micro o t3.micro]** |
| Par de claves | `vockey` (Paso 3) |
| Security Group | nuevo, `https-RSA-sg` (Paso 2) |
| Almacenamiento | 8 GiB gp3 (por defecto) |

Es una **instancia recién creada**, como pide el enunciado para las comprobaciones 1 y 2: así se ve la instalación completa de Apache desde cero.

📷 **Captura 01** – Resumen de la instancia en estado *Running* (tipo, AMI, Security Group).

![Captura 01 – Instancia EC2](img/01-instancia.png)

### Paso 2. Configurar el Security Group

**Dónde:** en el mismo asistente, *Network settings* → *Edit*, o después en EC2 → *Security Groups* → *Edit inbound rules*.

| Tipo | Protocolo | Puerto | Origen | Motivo |
|---|---|---|---|---|
| SSH | TCP | 22 | Mi IP | Administración remota, solo desde mi equipo |
| HTTP | TCP | 80 | 0.0.0.0/0 | Recibir peticiones HTTP para redirigirlas a HTTPS |
| HTTPS | TCP | 443 | 0.0.0.0/0 | Servir el sitio cifrado |

El puerto 80 se mantiene abierto aunque el sitio se sirva por HTTPS: si se cerrara, quien escriba `http://` en el navegador no recibiría la redirección y vería un error de conexión.

**[COMPLETAR: si dejas SSH abierto a 0.0.0.0/0 en vez de «Mi IP», cambia la tabla para que coincida con tu captura.]**

📷 **Captura 02** – Reglas de entrada del Security Group.

![Captura 02 – Security Group](img/02-security-group.png)

### Paso 3. Par de claves para SSH

**Dónde:** Learner Lab → *AWS Details* → *Download PEM* (descarga `labsuser.pem`, que es la clave privada del par `vockey`).

```bash
chmod 400 ~/Descargas/labsuser.pem
ssh -i ~/Descargas/labsuser.pem ubuntu@IP_ELASTICA
```

`chmod 400` deja la clave legible solo por mi usuario; si tiene más permisos, SSH la rechaza con `UNPROTECTED PRIVATE KEY FILE`.

**[COMPLETAR: si creas un par propio en vez de `vockey`, indica su nombre y por qué.]**

### Paso 4. Crear y asociar la IP elástica

**Dónde:** EC2 → *Network & Security* → *Elastic IPs* → *Allocate Elastic IP address* → *Allocate*. Después, con la IP seleccionada: *Actions* → *Associate Elastic IP address* → elegir la instancia `https-RSA` → *Associate*.

La IP pública normal cambia cada vez que la instancia se para y arranca. El certificado lleva la IP dentro del SAN y el archivo `hosts` de mi equipo apunta a ella, así que necesito una IP fija: si cambiara, habría que regenerar el certificado y editar el `hosts`.

IP elástica asignada: **[COMPLETAR: tu IP elástica]**

📷 **Captura 03** – IP elástica asociada a la instancia.

![Captura 03 – IP elástica](img/03-ip-elastica.png)

### Paso 5. Clonar el repositorio en la instancia

**5.1. Crear el repositorio y subir los archivos (desde mi equipo)**

**Dónde:** GitHub → *New repository* → nombre `practica-01-04`. Después, *Settings* → *Collaborators* → *Add people* → usuario del profesor.

```bash
cd practica-01-04
git init
git add .
git status            # comprobar que NO aparece scripts/.env ni ningún .key
git commit -m "Práctica 1.4: HTTPS con certificado autofirmado en Apache"
git branch -M main
git remote add origin https://github.com/rSainz21/practica-01-04.git
git push -u origin main
```

**5.2. Clonar y preparar el `.env` (en la instancia, por SSH)**

```bash
git clone https://github.com/rSainz21/practica-01-04.git
cd practica-01-04
cp scripts/.env.example scripts/.env
nano scripts/.env
```

En `nano` cambio `ELASTIC_IP` por mi IP elástica y, si quiero, los datos del sujeto (organización, email). Guardar con `Ctrl+O`, `Enter`, y salir con `Ctrl+X`. El `.env` solo existe en la instancia: no se sube al repositorio.

Si el repositorio es privado, `git clone` pide usuario y contraseña: la contraseña es un *Personal Access Token* de GitHub (*Settings* → *Developer settings* → *Personal access tokens*), no la contraseña de la cuenta.

**[COMPLETAR: indica si el repositorio es público o privado y cómo lo clonaste.]**

📷 **Captura 04** – `git clone` correcto y `ls -la scripts/` mostrando `.env` y `.env.example`.

### Paso 6. Script `install_apache.sh`

Instala Apache sin preguntas y deja el servicio habilitado y en marcha. Si Apache ya está instalado, avisa y termina sin hacer nada. La explicación de cada parte está en [Explicación de los scripts](#explicación-de-los-scripts).

### Paso 7. Script `setup_selfsigned_certificate.sh`

Comprueba que Apache está instalado, lee las variables del `.env`, crea el certificado con `subjectAltName`, copia las plantillas de `conf/` sustituyendo el dominio, habilita `ssl`, `rewrite` y el sitio HTTPS, y solo reinicia Apache si `apache2ctl configtest` da el visto bueno.

### Paso 8. Ejecutar los dos scripts en orden

```bash
sudo ./scripts/install_apache.sh
sudo ./scripts/setup_selfsigned_certificate.sh
```

El orden importa: el segundo script comprueba que Apache está instalado y, si no, se detiene pidiendo ejecutar antes el primero.

Si al lanzarlos sale `Permission denied`, los scripts han perdido el permiso de ejecución: `chmod +x scripts/*.sh`.

La salida del primero es la **Comprobación 1** y la de una segunda ejecución es la **Comprobación 2**.

📷 **Captura 05** – Salida completa de `setup_selfsigned_certificate.sh` (generación de la clave, `a2enmod`, `a2ensite`, `Syntax OK`).

```text
[COMPLETAR: pega aquí la salida de setup_selfsigned_certificate.sh]
```

Los puntos y signos `+` que imprime `openssl` mientras crea la clave son normales: indican la búsqueda de los números primos de la clave RSA.

### Paso 9. Resolver el dominio en mi equipo y acceder

`practica-https.test` no existe en DNS (el dominio `.test` está reservado para pruebas), así que lo resuelvo a mano en el archivo `hosts` de **mi equipo** (Linux):

```bash
sudo nano /etc/hosts
```

Añado al final esta línea con mi IP elástica:

```text
IP_ELASTICA    practica-https.test
```

```bash
getent hosts practica-https.test    # debe devolver mi IP elástica
```

Accesos probados desde el navegador:

| URL | Resultado esperado |
|---|---|
| `http://practica-https.test` | Redirige a `https://practica-https.test/` y muestra el aviso de certificado |
| `https://practica-https.test` | Aviso de CA no confiable; tras aceptarlo, la página de Apache |
| `http://IP_ELASTICA` | Redirige a `https://IP_ELASTICA/` |
| `https://IP_ELASTICA` | Aviso de CA no confiable, pero **sin** error de nombre, porque la IP está en el SAN |

**[COMPLETAR: confirma que los cuatro accesos se comportan así.]**

📷 **Captura 06** – Archivo `/etc/hosts` con la línea añadida.

### Paso 10. Comprobaciones y evidencias

Ver el apartado [Verificación y evidencias](#verificación-y-evidencias).

### Paso 11. Detener la instancia y liberar la IP elástica

**Dónde:** EC2 → *Instances* → `https-RSA` → *Instance state* → *Stop instance*.

Si no voy a seguir usándola: EC2 → *Elastic IPs* → seleccionar la IP → *Actions* → *Disassociate Elastic IP address* y después *Release Elastic IP addresses*. AWS cobra por hora cada IPv4 pública, y una IP elástica reservada sigue gastando crédito aunque la instancia esté parada.

**[COMPLETAR: indica si paraste la instancia o liberaste también la IP.]**

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

Si se vuelve a ejecutar, el script genera un certificado nuevo y vuelve a copiar las plantillas, con el mismo resultado.

### Plantillas de `conf/`

**`000-default.conf`** (puerto 80): `RewriteRule ^ https://%{HTTP_HOST}%{REQUEST_URI} [L,R=301]` redirige cualquier URL (`^`) a la misma dirección con `https://`, conservando el host y la ruta. `R=301` es una redirección permanente y `L` detiene el procesado de reglas. No hace falta `RewriteCond %{HTTPS} off`, porque en el puerto 80 la conexión nunca es HTTPS.

**`practica-https-ssl.conf`** (puerto 443): `SSLEngine on` activa TLS en el virtual host, y `SSLCertificateFile` y `SSLCertificateKeyFile` apuntan al certificado y a la clave creados por el script. Tiene logs propios (`practica-https-error.log` y `practica-https-access.log`) para separar el tráfico HTTPS. Es un archivo propio, en vez de modificar `default-ssl.conf`.

### `.env.example` y `.gitignore`

`.env.example` documenta todas las variables con valores de ejemplo (la IP `203.0.113.10` es de un rango reservado para documentación). El `.env` real se crea copiándolo en la instancia. `.gitignore` excluye `.env`, `scripts/.env` y los ficheros de claves (`*.key`, `*.pem`, `*.csr`, `*.p12`, `*.pfx`), para que nunca se suban al repositorio aunque se haga `git add .`.

---

## Verificación y evidencias

Las comprobaciones 1 a 5 se hacen **en la instancia**. Las 6 a 9 se hacen **desde mi equipo**, porque solo mi `/etc/hosts` resuelve `practica-https.test` y así se comprueba también el Security Group.

### Comprobación 1. Instalación de Apache

```bash
sudo ./scripts/install_apache.sh
systemctl status apache2
```

**Esperado:** Apache se instala sin preguntas; el servicio aparece `active (running)` y `enabled`.

```text
[COMPLETAR: pega la salida del script y de systemctl status apache2]
```

### Comprobación 2. Reejecución del script de instalación

```bash
sudo ./scripts/install_apache.sh
```

**Esperado:** solo el mensaje `Apache ya está instalado.`, sin volver a instalar nada.

```text
[COMPLETAR: pega la salida]
```

### Comprobación 3. Sujeto, validez y SAN del certificado

```bash
openssl x509 -in /etc/ssl/certs/apache-selfsigned.crt -noout -subject -dates -ext subjectAltName
```

**Esperado:** los datos del `.env`, 365 días entre `notBefore` y `notAfter`, y el dominio y la IP en el SAN. Debe parecerse a esto:

```text
subject=C = ES, ST = Cantabria, L = Torrelavega, O = ..., OU = Informatica, CN = practica-https.test, emailAddress = ...
notBefore=... 2026 GMT
notAfter=... 2027 GMT
X509v3 Subject Alternative Name:
    DNS:practica-https.test, IP Address:IP_ELASTICA
```

```text
[COMPLETAR: pega tu salida real]
```

### Comprobación 4. Sintaxis de Apache

```bash
sudo apache2ctl configtest
```

**Esperado:** `Syntax OK`.

```text
[COMPLETAR: pega la salida]
```

Puede aparecer antes el aviso `AH00558: apache2: Could not reliably determine the server's fully qualified domain name`. No es un error: indica que no hay `ServerName` en la configuración global (solo en los virtual hosts) y no impide que Apache funcione.

### Comprobación 5. Puertos a la escucha

```bash
sudo ss -tlnp | grep apache2
```

**Esperado:** dos líneas `LISTEN`, una en `*:80` y otra en `*:443`, del proceso `apache2`.

```text
[COMPLETAR: pega la salida]
```

### Comprobación 6. Redirección HTTP → HTTPS (desde mi equipo)

```bash
curl -I http://practica-https.test
```

**Esperado:** `HTTP/1.1 301 Moved Permanently` y la cabecera `Location: https://practica-https.test/`.

```text
[COMPLETAR: pega la salida]
```

### Comprobación 7. Respuesta HTTPS (desde mi equipo)

```bash
curl -kI https://practica-https.test
```

**Esperado:** `HTTP/1.1 200 OK`. La opción `-k` hace que `curl` acepte el certificado aunque no sea de confianza; sin ella fallaría con `SSL certificate problem: self-signed certificate`.

```text
[COMPLETAR: pega la salida]
```

### Comprobación 8. Negociación TLS (desde mi equipo)

```bash
openssl s_client -connect practica-https.test:443 -servername practica-https.test < /dev/null
```

**Esperado:** en la salida hay que localizar:

- **Certificado presentado:** en `Certificate chain`, el sujeto (`s:`) y el emisor (`i:`) son el mismo, porque es autofirmado.
- **Versión TLS y cifrado:** una línea como `New, TLSv1.3, Cipher is TLS_AES_256_GCM_SHA384`.
- **Verificación:** `Verify return code: 18 (self-signed certificate)`, que confirma que el cifrado funciona pero el certificado no está firmado por una CA de confianza.

`< /dev/null` cierra la entrada para que `s_client` termine en lugar de quedarse esperando.

```text
[COMPLETAR: pega la salida, o al menos las partes anteriores]
```

Versión TLS y cifrado negociados: **[COMPLETAR]**

### Comprobación 9. Navegador

Acceso a `https://practica-https.test`.

**Esperado:** aviso de CA no confiable (en Firefox, «Advertencia: riesgo potencial de seguridad» con `SEC_ERROR_UNKNOWN_ISSUER`; en Chrome, «La conexión no es privada» con `NET::ERR_CERT_AUTHORITY_INVALID`). Tras aceptar el riesgo, se ve la página de Apache. En los detalles del certificado (clic en el icono a la izquierda de la URL → certificado) el emisor y el sujeto coinciden, y en *Nombre alternativo del sujeto* aparecen el dominio y la IP.

📷 **Captura 07** – Aviso de seguridad del navegador.

![Captura 07 – Aviso del navegador](img/07-aviso-navegador.png)

📷 **Captura 08** – Página servida por HTTPS tras aceptar el aviso.

![Captura 08 – Web por HTTPS](img/08-web-https.png)

📷 **Captura 09** – Detalles del certificado (sujeto, emisor, validez y SAN).

![Captura 09 – Detalles del certificado](img/09-detalles-certificado.png)

---

## Incidencias y resolución

**[COMPLETAR: deja solo las que te hayan pasado de verdad y añade las tuyas.]**

| Incidencia | Causa | Solución |
|---|---|---|
| `Could not get lock /var/lib/dpkg/lock-frontend` | `unattended-upgrades` actualizando la instancia recién creada | El script espera hasta 5 minutos con `DPkg::Lock::Timeout=300` |
| `Permission denied` al ejecutar `./scripts/...` | Los scripts no tienen permiso de ejecución | `chmod +x scripts/*.sh` |
| `$'\r': command not found` | El archivo tiene saltos de línea de Windows (CRLF) | `sed -i 's/\r$//' scripts/*.sh scripts/.env conf/*.conf` |
| `ERR_NAME_NOT_RESOLVED` / `Could not resolve host` | Falta la línea en `/etc/hosts` de mi equipo, o se ejecutó `curl` desde la instancia | Añadir la línea del Paso 9 y lanzar las comprobaciones 6-8 desde mi equipo |
| `curl` se queda esperando en `https://` | Falta la regla del puerto 443 en el Security Group | Añadir HTTPS (TCP 443) en las reglas de entrada |
| Aviso `AH00558` en `configtest` | No hay `ServerName` global | Es un aviso, no un error; la sintaxis es correcta |

---

## Conclusiones

**[COMPLETAR: redáctalas con tus palabras. Ideas de base:]**

- Automatizar con scripts permite repetir el despliegue en una instancia nueva sin pasos manuales y sin errores de copia, y comprobar el estado antes de actuar (`dpkg -s`, `configtest`) hace que los scripts sean seguros de reejecutar.
- Separar la configuración (`.env`) del código (scripts y plantillas) permite publicar el repositorio sin exponer la IP, los datos personales ni la clave privada.
- El certificado autofirmado cifra igual que uno de una CA, pero no demuestra la identidad del servidor ante el navegador. Para un sitio público habría que usar una CA, por ejemplo Let's Encrypt.
- **[COMPLETAR: algo que hayas aprendido o te haya costado.]**

---

## Fuentes

- Apache HTTP Server 2.4 – `mod_ssl`: https://httpd.apache.org/docs/2.4/mod/mod_ssl.html
- Apache HTTP Server 2.4 – `mod_rewrite`: https://httpd.apache.org/docs/2.4/mod/mod_rewrite.html
- OpenSSL – `openssl-req`: https://docs.openssl.org/3.0/man1/openssl-req/
- AWS – Direcciones IP elásticas: https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/elastic-ip-addresses-eip.html
- RFC 6761 – Nombres de dominio de uso especial (`.test`): https://www.rfc-editor.org/rfc/rfc6761
- Enunciado de la Actividad 2.2 (Práctica 1.4), DAW2, curso 2026-2027.
