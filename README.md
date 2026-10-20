# Pomobicho

Um gatinho flutuante para Windows que acompanha seus pomodoros, com temas, tamanho ajustável e um aviso no segundo monitor.

## Recursos

- Foco de **30 minutos** e pausa de **5 minutos**, configuráveis.
- Timer com iniciar, pausar, retomar e reiniciar.
- Janela transparente, arrastável e sempre por cima dos aplicativos.
- Tamanho de **35% a 150%**, com ajuste ao vivo.
- Sete temas: Escuro, Claro, Rosa, Lavanda, Terminal hacker, HUD futurista e Arcade retrô.
- Temas que também mudam moldura, tipografia, controles e decoração.
- Efeitos opcionais: varredura no Terminal e anel giratório no HUD.
- Configurações em popup, com fechar por **×** ou **Esc**.
- Ao terminar o foco, um gatinho pisca suavemente no monitor `DISPLAY2` até ser dispensado com um clique.
- Preferências e posição salvas localmente.

## Executar

Requer **Windows**, **Windows PowerShell 5.1** e **WPF**. Não utiliza serviços externos para funcionar.

1. Baixe ou clone o repositório.
2. Mantenha `Pomobicho.ps1`, `gatinho-laco.png` e `Abrir Pomobicho.vbs` juntos.
3. Abra **Abrir Pomobicho.vbs** com dois cliques.

Se arquivos VBS estiverem desabilitados, abra um terminal na pasta e execute:

```powershell
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\Pomobicho.ps1
```

A opção de execução vale apenas para esse processo; o comando não altera a política global do Windows.

## Controles

| Ação | Como fazer |
| --- | --- |
| Mover | Arrastar pelo gatinho |
| Ajustar tamanho | Barra nas configurações, botões − / + ou Ctrl + rodinha do mouse |
| Trocar tema | Clique direito → Tema |
| Abrir configurações | Engrenagem; no tema Terminal, botão `>` |
| Testar aviso | Clique direito → Testar aviso no monitor 2 |
| Fechar | Clique direito → Fechar bichinho |

Mudanças de tema e tamanho são aplicadas e salvas na hora. A alteração da duração durante um período em andamento vale para o próximo período; reinicie o timer para aplicá-la imediatamente.

## Aviso de conclusão

O aviso aparece no canto inferior direito do monitor identificado pelo Windows como `DISPLAY2`. Se ele estiver desconectado, o monitor principal é usado. O aviso não toma o foco do teclado e fica visível até receber um clique.

O fim da pausa não dispara esse aviso. A pausa automática não impede o aviso de conclusão do foco. O som depende das preferências do app e do esquema de sons do Windows.

## Komorebi

O popup usa os estilos nativos `WS_POPUP` e `WS_EX_TOOLWINDOW`, sem moldura e sem entrada na barra de tarefas. Ao abrir as configurações, o app também tenta registrar uma regra específica com `komorebic ignore-rule`. Essa integração é opcional e depende da disponibilidade do cliente e da comunicação com o Komorebi.

## Preferências e limitações

- `preferencias.json` é criado ao lado do script e está fora do controle de versão.
- A pasta precisa permitir gravação para salvar preferências.
- Fechar o app encerra o timer; ele não é restaurado automaticamente ao abrir.
- O tempo em suspensão conta para a duração. O aviso aparece quando o computador volta.
- Janelas de segurança e alguns aplicativos em tela cheia podem cobrir o bichinho.
- O app não inicia automaticamente com o Windows.

## Verificação

Execute os testes locais com Windows PowerShell:

```powershell
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\Pomobicho.ps1 -SelfTest
```

Os testes verificam timer, pausa, conclusão, temas, efeitos, redimensionamento, estilos nativos do popup e disparo do aviso. Algumas janelas de teste aparecem brevemente.

Para produzir capturas e verificar também a persistência em um arquivo de teste:

```powershell
New-Item -ItemType Directory -Force .\work | Out-Null
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\Pomobicho.ps1 -SelfTest -PreviewPath "$PWD\work\test-preview.png"
```

## Arquivos

- `Pomobicho.ps1`: aplicativo WPF e testes.
- `gatinho-laco.png`: arte do gatinho com transparência.
- `Abrir Pomobicho.vbs`: inicializador sem console.
- `LEIA-ME.txt`: instruções locais.
- `ASSETS.md`: origem da arte.
