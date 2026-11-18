## [1.29.0] - 2026-11-18

### Added
- o onboarding pergunta primeiro o estilo, GuildOS ou WoW: Forever, e o reload que a escolha pede só acontece ao concluir (#375)
- Conquistas vira a primeira subaba da Guilda e onde ela abre, e cada conquista mostra um tooltip com o que pede, quando e por quem saiu, ou quanto falta (#373)
- Diário e Conquistas ganham destaques, cartões e coleção, Grupos vira cartões de atividade e Recrutamento um painel com prévia do anúncio (#373)
- Guilda, Recrutamento, Raides, Loot, Grupos, Aliança, Liderança, Web e Profissões passam a usar os mesmos títulos, campos, tabelas e seleção, sem ouro de enfeite e com uma margem só (#371)
- a barra de rolagem some quando nada rola e o conteúdo não passa mais por baixo dela; título de seção, campo, cabeçalho de tabela e seleção ganham um componente único (#371)
- o Configurações se reorganiza em seis subabas, montadas uma vez, com uma faixa única para recarregar (#367)
- Trials vira subaba de Recrutamento, Diário e Conquistas viram subabas de Guilda, e o Conselho de Loot ganha botão na janela de Loot (#367)
- nas telas de raide, wishlist, configurações e membros o ouro sai do texto e fica só na seleção, e os números das tabelas vão para a Plex Mono (#363)
- o estilo GuildOS ganha a identidade Swiss 2.0, com IBM Plex Sans, contraste AA e o ouro só onde marca (#361)

### Fixed
- concluir o onboarding recarrega antes de fechar a janela, porque no WoW: Forever o clique que escondia o assistente primeiro não podia mais recarregar (#375)
- concluir o onboarding em combate não tenta mais recarregar, o que o jogo bloqueia; o reload do estilo é oferecido assim que o combate acaba (#375)
- a lista aberta dos menus de seleção ganha fundo e borda, e as opções não flutuam mais sobre o que está atrás (#371)
- as caixas de várias linhas (opções da enquete, MOTD e informações da guilda) mantêm a altura, e Loot > Listas mostra "My Wishlist" uma vez só (#371)
- Liderança > Ranks e Inatividade desenham só as linhas que cabem, e a lista de 943 membros aparece (#371)
- Liderança > Ranks volta a listar os membros, e as listas de Liderança não somem mais quando a aba é montada escondida (#371)
- a borda das caixas de seleção não perde mais os lados direito e de baixo em escalas menores (#369)
- as bordas e linhas de 1px não somem mais quando a interface está em escala menor, e voltam ao pixel certo quando a escala muda (#369)
