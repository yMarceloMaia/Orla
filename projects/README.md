# Projetos na Orla

Em **Configurações → Widgets**, habilite **Recursos dos projetos**, **Comandos dos projetos** ou ambos. Eles compartilham um único registro e um auxiliar Python por sessão. Os serviços dos projetos rodam como o usuário, em unidades transitórias do systemd.

## Cadastrar e monitorar

**Adicionar pasta** registra o diretório informado. **Descobrir projetos** registra a pasta se ela tiver marcadores de projeto ou procura nos seus filhos diretos. A Orla volta a verificar as pastas de descoberta e respeita projetos removidos manualmente. Renomeie o projeto em **Configurar**. O ID interno permanece estável.

O monitor usa o cgroup das execuções da Orla para identificar processos gerenciados. Para processos externos, usa diretório de trabalho, caminhos absolutos nos argumentos e ascendência. Essas associações são estimativas. CPU de 100% corresponde a um núcleo. O triângulo marca processos com pelo menos 90% de um núcleo na amostra. A memória local usa PSS quando disponível e identifica a aproximação por RSS. Os contadores de disco são acumulados desde o início do processo. A lista de portas mostra sockets observáveis no namespace de rede da sessão. O monitor não estima tráfego por processo.

Em **Intervalos**, configure segundos com o painel aberto e fechado. Os padrões são 4 e 30 segundos. O histórico de CPU e RAM mantém 60 amostras por projeto e reinicia com o auxiliar. A cada descoberta completa em `/proc`, o monitor guarda os PIDs relevantes para as leituras seguintes.

## Docker

Habilite o Docker Manager para compartilhar seus dados. Em **Configurar**, informe os nomes Compose separados por vírgula. Se o Docker Manager fornecer uma pasta Compose local válida, **Importar Compose** permite registrá-la diretamente. Um nome Compose pode pertencer a um único projeto.

As métricas dos containers aparecem separadas das locais. O painel marca medições parciais quando o Engine fornece apenas metadados. A autenticação continua pelo Docker Manager e segue a duração da sua sessão de leitura. Se já instalou o auxiliar privilegiado de uma versão anterior, atualize-o conforme a seção **Docker Manager** do README para receber serviço, pasta Compose e saúde no modo autenticado.

## Executar comandos

A descoberta lê scripts de package.json, alvos simples de Makefile, receitas de justfile, tarefas de Taskfile e serviços Compose. Para scripts JavaScript, o campo packageManager tem prioridade sobre os lockfiles. A descoberta de Taskfile e Compose usa **PyYAML** (pacote Arch `python-yaml`). O executável correspondente ao comando deve estar no PATH do serviço de usuário.

1. Abra um projeto no widget de comandos e escolha **Executar** em um comando descoberto. Use **Editar** para ajustar sua configuração.
2. Informe o executável e os argumentos como uma lista, por exemplo `["python", "-m", "http.server", "8000"]`. Em comandos descobertos, esse campo acompanha o arquivo de origem. O diretório de execução deve estar dentro do projeto.
3. Em **Prontidão, dependências e ambiente**, use `depends` para referenciar os IDs das etapas anteriores. O painel exibe cada ID na lista. **Executar** inclui as dependências do comando selecionado.
4. Configure `ready` conforme o serviço. Exemplos: `{"type":"tcp","host":"127.0.0.1","port":5432}`, `{"type":"http","url":"http://localhost:8000/health"}`, `{"type":"docker","project":"meu-projeto","service":"db"}` e `{"type":"process"}`. O teste Docker requer dados recentes do Docker Manager e um health check configurado no container. O timeout padrão é de 120 segundos.
5. Use **Parar** na execução para encerrar a unidade gerenciada. Comandos que iniciam serviços do Docker requerem acesso ao Engine no ambiente de execução. A autorização de leitura do widget não eleva comandos de projeto.

A interface inicia comandos apenas por ação do usuário. Execuções ativas continuam supervisionadas se você fechar ou reiniciar a dock. **Logs** abre o terminal padrão via `xdg-terminal-exec` para acompanhar stdout e stderr. O painel também permite pesquisar as últimas 150 linhas por execução. O histórico guarda as últimas 100 execuções terminadas e as ativas. **Reiniciar** substitui uma execução ativa. **Executar novamente** usa a definição atual do comando.

## Configuração e privacidade

O registro e o histórico ficam em `$XDG_STATE_HOME/orla/projects/`, normalmente `~/.local/state/orla/projects/`, em um diretório privado da conta. Informe referências a variáveis já presentes no ambiente do systemd de usuário, por exemplo `"env":{"API_TOKEN":"DEV_API_TOKEN"}`. A Orla resolve o valor no início da execução. Para shell explícito, informe o executável e seus argumentos e habilite `"shell":true`.

Os logs filtram linhas com nomes ou formatos comuns de credenciais, blocos de chave privada e valores explicitamente fornecidos por referência de ambiente. Para comandos que imprimem conteúdo confidencial arbitrário, use `"capture":false` para suprimir a saída. O diretório do projeto, a definição do comando e o histórico pertencem ao usuário local.

## Testes

Execute `python tests/test_projects.py -v` em uma sessão Linux com systemd de usuário, Node.js e PyYAML. A suíte cria projetos temporários, usa unidades reais e remove seus processos ao terminar. O teste Docker ao vivo requer acesso de leitura ao Engine e pelo menos dois containers Compose ativos.
