<p align="center">
  <img src="assets/logo.svg" alt="VPS Snapshot" width="480">
</p>

<p align="center">
  <a href="README.md">English</a> · <strong>Portugues</strong>
</p>

<p align="center">
  <strong>Backup completo da sua VPS para a nuvem. Um comando pra instalar, um comando pra rodar.</strong>
</p>

<p align="center">
  <a href="#-inicio-rapido">Inicio Rapido</a> ·
  <a href="#-recursos">Recursos</a> ·
  <a href="#-provedores-suportados">Provedores</a> ·
  <a href="#%EF%B8%8F-configuracao">Configuracao</a> ·
  <a href="#-seguranca">Seguranca</a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Bun-1.0.0-black?style=flat-square&logo=bun&logoColor=white" alt="Bun">
  <img src="https://img.shields.io/badge/Licenca-MIT-blue?style=flat-square" alt="MIT License">
  <img src="https://img.shields.io/badge/Linux-x86__64%20%7C%20ARM64-yellow?style=flat-square&logo=linux&logoColor=white" alt="Linux">
  <img src="https://img.shields.io/badge/Nuvem-70%2B%20provedores-ff69b4?style=flat-square" alt="Provedores">
  <img src="https://img.shields.io/badge/Instalar-1%20comando-success?style=flat-square" alt="Um comando">
</p>

---

## Por que?

A maioria das ferramentas de backup de VPS sao complexas demais (Borg, Duplicity) ou limitadas demais (cron + rsync simples). **VPS Snapshot acerta o meio termo** — snapshot completo do disco com restauracao seletiva, criptografado, verificado e pronto em 60 segundos.

**O problema que resolve:** Sua VPS tem configs customizadas, scripts, chaves SSH, cron jobs, setups de Docker que levaram horas pra configurar. Se ela morrer, voce comeca do zero. VPS Snapshot captura *tudo* e deixa voce restaurar *exatamente* o que precisa.

---

## Inicio Rapido

```bash
# Instalar (um comando — instalador interativo)
curl -sSL https://raw.githubusercontent.com/amonmelo/vps-snapshot/main/install.sh | sudo bash
```

So isso. O instalador cuida de tudo:

```
 ╔═══════════════════════════════════════════════════╗
 ║           VPS SNAPSHOT                            ║
 ║           Backup completo da sua VPS              ║
 ║           Feito com Bun — rapido e seguro         ║
 ╚═══════════════════════════════════════════════════╝

  Sistema: my-server
  Kernel:  6.6.87 (x86_64)
  Disco:   45G livres

  ? Nome desta VPS [my-server]:
  ? Provedor [OneDrive (5 GB gratis)]:
  ? Frequencia [Diario as 3h (recomendado)]:
  ? Compressao (1=rapido 9=maximo) [6]:
  ? Criptografar backups com GPG? [s/N]:

  [✓] Bun 1.3.13 instalado
  [✓] rclone instalado
  [✓] pigz instalado (compressao paralela disponivel)
  [✓] Cron: Diario 3h

  Comandos:
    sudo vps-snapshot estimate    Estimar tamanho
    sudo vps-snapshot             Backup manual
    sudo vps-snapshot list        Listar backups
```

### Primeiro backup

```bash
# Estimar tamanho primeiro (recomendado)
sudo vps-snapshot estimate

# Rodar o primeiro backup
sudo vps-snapshot
```

### Restaurar

```bash
# Listar backups disponiveis
sudo vps-snapshot list

# Navegar o conteudo
sudo vps-snapshot browse 20250601150000

# Extrair caminhos especificos
sudo vps-snapshot extract 20250601150000 /etc/nginx /home/user --dest /tmp/restored

# Restauracao completa (em uma VPS nova!)
sudo vps-snapshot full 20250601150000
```

---

## Recursos

- **Instalacao em um comando** — Instalador interativo guiado, zero conhecimento de dependencias necessario
- **Snapshot completo do disco** — Captura `/root`, `/home`, `/etc`, `/opt`, `/var`, configs do Docker, cron jobs, chaves SSH, servicos systemd
- **Restauracao seletiva** — Extraia so `/etc/nginx` ou `/home/user`, nao o backup inteiro
- **Modo browse** — Navegue o conteudo do backup sem baixar tudo
- **70+ provedores de nuvem** — OneDrive, Google Drive, Dropbox, S3, Backblaze, SFTP e mais via rclone
- **Criptografia GPG** — AES-256 simetrica ou chave publica (opcional)
- **Verificacao SHA-256** — Checagem de integridade obrigatoria no upload e download. Falha fechada, nunca silenciosa.
- **Auto-split** — Divide backups grandes em partes de 4GB (limite do OneDrive)
- **Compressao paralela** — Usa `pigz` quando disponivel, fallback para `gzip`
- **Rotacao automatica** — Mantenha N backups, os mais antigos sao excluidos automaticamente
- **Agendamento via Cron** — Diario, semanal, quinzenal, mensal ou manual
- **Funciona em qualquer lugar** — Ubuntu, Debian, CentOS, Fedora, Arch, Alpine, SUSE, qualquer Linux x86_64 ou ARM64

---

## Provedores Suportados

| Provedor | Espaco Gratis | Configuracao |
|----------|---------------|--------------|
| Microsoft OneDrive | 5 GB | OAuth (browser ou token) |
| Google Drive | 15 GB | OAuth |
| MEGA | 20 GB | OAuth |
| Backblaze B2 | 10 GB | Chave de API |
| pCloud | 10 GB | OAuth |
| Dropbox | 2 GB | OAuth |
| Amazon S3 | 5 GB | Chave de acesso |
| SFTP | — | Host + credenciais |

...e mais 60+ via [rclone](https://rclone.org/#providers).

---

## Como Funciona

```
tar (raiz /)
  → pigz (compressao paralela)
    → [GPG criptografa]
      → split (partes de 4GB)
        → manifesto SHA-256
          → rclone upload
            → verifica integridade
```

**O que entra no backup:** Tudo no disco — configs do sistema, arquivos do usuario, setups Docker, chaves SSH, cron jobs, servicos systemd, scripts customizados.

**O que e excluido** (automatico):

| Categoria | Caminhos |
|-----------|----------|
| Filesystems virtuais | `/proc`, `/sys`, `/dev`, `/run` |
| Caches de pacotes | `/var/cache/apt`, `/var/cache/yum`, `/var/cache/dnf` |
| Caches de linguagens | `node_modules`, `__pycache__`, `.cache`, `.npm` |
| Caches de build | `.cargo/registry`, `go/pkg/mod` |
| Imagens Docker | `/var/lib/docker/*` (opcional) |
| Swap | `/swapfile` |
| A propria ferramenta | `/opt/vps-snapshot` |

Todas as exclusoes sao configuraveis via `config.json`.

---

## Configuracao

Edite `/opt/vps-snapshot/config.json` apos a instalacao:

```json
{
  "vpsName": "my-server",
  "remoteName": "onedrive",
  "remotePath": "Backup-VPS",
  "keepBackups": 5,
  "compressionLevel": 6,
  "splitSize": "4G",
  "excludeDockerImages": true,
  "encryption": {
    "enabled": false,
    "passphrase": "",
    "recipient": ""
  },
  "includeSystemInfo": false
}
```

<details>
<summary>Referencia completa de configuracao</summary>

| Campo | Tipo | Padrao | Descricao |
|-------|------|--------|-----------|
| `vpsName` | string | hostname | Identificador da VPS (usado na estrutura de pastas na nuvem) |
| `remoteName` | string | `onedrive` | Nome do remote do rclone |
| `remotePath` | string | `Backup-VPS` | Pasta raiz no provedor de nuvem |
| `keepBackups` | number | `5` | Maximo de backups para manter (rotacao automatica) |
| `compressionLevel` | number | `6` | 1 (rapido) a 9 (maximo) |
| `splitSize` | string | `4G` | Tamanho maximo por parte (limite de upload na nuvem) |
| `excludeDockerImages` | bool | `false` | Excluir camadas de imagens Docker (~2GB+ de economia) |
| `excludePatterns` | string[] | `["*.log", ...]` | Padroes glob para excluir |
| `excludePaths` | string[] | `["/proc", ...]` | Caminhos absolutos para excluir |
| `preBackupCommands` | string[] | `[]` | Comandos shell antes do backup |
| `postBackupCommands` | string[] | `[]` | Comandos shell depois do backup |
| `includeSystemInfo` | bool | `false` | Incluir hostname/distro nos metadados |
| `encryption.enabled` | bool | `false` | Ativar criptografia GPG |
| `encryption.passphrase` | string | `""` | Senha simetrica (AES-256) |
| `encryption.recipient` | string | `""` | Email do destinatario GPG (chave publica) |

</details>

---

## Todos os Comandos

| Comando | Descricao |
|---------|-----------|
| `vps-snapshot` | Rodar backup |
| `vps-snapshot estimate` | Estimar tamanho do backup |
| `vps-snapshot list` | Listar backups na nuvem |
| `vps-snapshot browse [ts]` | Navegar conteudo do backup |
| `vps-snapshot extract <ts> <paths> [--dest /dir]` | Extrair caminhos especificos |
| `vps-snapshot full [ts]` | Restauracao completa (VPS nova) |
| `vps-snapshot log [N]` | Mostrar ultimas N linhas do log |
| `vps-snapshot status` | Status do provedor + espaco |
| `vps-snapshot config` | Exibir configuracao atual |

Flags globais: `-v` (verbose), `-c /caminho/config.json` (config customizada), `-h` (ajuda)

---

## Seguranca

| Camada | Implementacao |
|--------|---------------|
| **Sem eval** | Todos os comandos shell usam `Bun.spawn()` com arrays de argumentos — nunca interpolacao de strings |
| **Lock imprevisivel** | `flock` com caminho `mktemp` — previne ataques de symlink em `/tmp` |
| **Sanitizacao de input** | O instalador escapa `\ " \n \r \t` antes de escrever `config.json` — previne JSON injection |
| **Controle de PII** | Hostname, distro, kernel excluidos dos metadados por padrao (`includeSystemInfo: false`) |
| **Integridade obrigatoria** | SHA-256 verificado em todo download — `die()` em divergencia, nunca silencioso |
| **Restauracao protegida** | `validateDestDir()` bloqueia extracao para `/`, `/bin`, `/usr`, `/etc`, `/boot` |
| **Path traversal** | `validatePath()` rejeita `..` em todos os caminhos fornecidos pelo usuario |
| **Criptografia GPG** | AES-256 simetrica ou chave publica. Senha armazenada em `config.json` com `chmod 600` |
| **Validacao de timestamp** | Forca formato `YYYYMMDDHHmmss` com verificacao de intervalo |

---

## Arquitetura

```
vps-snapshot/
  install.sh          Instalador interativo (474 linhas, bash)
  src/
    index.ts          Ponto de entrada — parse de args + dispatch
    config.ts         Loader de config + validacao de input
    logger.ts         Logging padronizado [ERROR/SUCCESS/INFO/WARN/DEBUG]
    backup.ts         Motor de backup — tar, comprime, criptografa, splita, uploada
    restore.ts        Motor de restauracao — list, browse, extract, full
    utils.ts          rclone, flock, retry, mktemp, sha256, GPG, pigz
```

**Runtime:** [Bun](https://bun.sh/) — 3x mais rapido que Node.js, TypeScript nativo, zero config.
**Transporte:** [rclone](https://rclone.org/) — testado em batalha, 70+ backends de nuvem, OAuth tokens com auto-refresh.

---

## Requisitos

- Linux (x86_64 ou ARM64)
- Acesso root
- Conexao com a internet
- 1 GB+ livre em `/tmp`

O instalador cuida de todas as dependencias automaticamente:
- Bun, rclone, pigz, GPG (se criptografia ativada), zip, curl

---

## Desinstalar

```bash
sudo rm -rf /opt/vps-snapshot
sudo rm /usr/local/bin/vps-snapshot
sudo rm /etc/cron.d/vps-snapshot
```

---

## Licenca

[MIT](LICENSE) — use como quiser.

---

<p align="center">
  Feito com <a href="https://bun.sh/">Bun</a> · Movido por <a href="https://rclone.org/">rclone</a>
</p>
