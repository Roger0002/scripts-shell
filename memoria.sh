#!/usr/bin/env bash

# Script de verificação de percentual de utilização de memória
# Versão 1.0
# Desenvolvido por Roger Príncipe

# Testa versão do S.O. para sabermos se trata-se de um RHEL7. Essa informação será importante quando verificarmos a quantidade de memória RAM total e em uso
grep -E " 7.*?Maipo\)" /etc/redhat-release > /dev/null 2>&1 && VER_SO="rhel7"

# Variável que captura a frequência de atualização fornecida pelo usuário. Deve ser um número entre 1 e 9. Caso o usuário não informe nada ou informe um dado incoerente, será de um segundo.
if [[ "$1" =~ ^[1-9]$ ]]; then
        freq_atl=$1
else
        freq_atl=1
fi

# Trata a ativação das teclas Ctrl + C para exibir uma mensagem ao sair do script
trap "echo -e '\nCtrl + C pressionado. Saindo...\n'; exit" SIGINT

# Trata o recebimento de um sinal SIGTERM pelo script para o caso de alguém mandar um kill no processo (não funcionará com kill -9). Exibirá uma mensagem de aviso de saída
trap "echo -e '\nScript finalizado por interferencia externa. Saindo...\n'; exit" SIGTERM

# Início do Loop que irá exibir utilização da memória a cada segundo
while true; do

        # Quadrado branco mostrado nas barras de consumo
        quadrado=$(echo -e "\e[7m \e[27m")

        # Variaveis contendo métricas de memória fisica
        ramtotal=$(free -m | grep -i 'mem' | awk '{print $2}')
        if [ "$VER_SO" != "rhel7" ]; then
                ramem_uso=$(free -m | grep -i 'buffers/' | awk '{print $3}')
        else
                ramem_uso=$(free -m | grep -i 'Mem:' | awk '{print $3}')
        fi
        percentual_uso=$(((100*ramem_uso)/$ramtotal))

        # Variáveis contendo métricas de swap
        swaptotal=$(free -m | grep -i swap | awk '{print $2}')
        swapem_uso=$(free -m | grep -i swap | awk '{print $3}')
        if [ "$swaptotal" -eq 0 ]; then
                percentual_swap_uso=0
        else
                percentual_swap_uso=$(((100*$swapem_uso)/$swaptotal))
        fi

        # Variáveis contendo métricas de memória virtual (RAM + Swap)
        virtualtotal=$((${ramtotal}+${swaptotal}))
        virtualem_uso=$((${ramem_uso}+${swapem_uso}))
        percentual_virtual_uso=$(((100*$virtualem_uso)/$virtualtotal))

        # Variáveis que recebem os construtores das barras de consumo
        barra_ram=$((echo '['
        for bloco in $(seq 1 $(echo $percentual_uso)); do
                echo "$quadrado"
                done
        for bloco in $(seq 1 $((100-$percentual_uso))); do
                echo '_'
                done) | tr -d "\n"; echo ']' | tr -d "\n"; echo ""
        echo " ${percentual_uso}% da memoria RAM em uso ($ramem_uso MB)")

        barra_swap=$((echo '['
        for bloco in $(seq 1 $(echo $percentual_swap_uso)); do
                echo "$quadrado"
                done
        for bloco in $(seq 1 $((100-$percentual_swap_uso))); do
                echo '_'
                done) | tr -d "\n"; echo ']'
        echo " ${percentual_swap_uso}% da Swap em uso ($swapem_uso MB)")

        barra_virtual=$((echo '['
        for bloco in $(seq 1 $(echo $percentual_virtual_uso)); do
                echo "$quadrado"
                done
        for bloco in $(seq 1 $((100-$percentual_virtual_uso))); do
                echo '_'
                done) | tr -d "\n"; echo ']'
        echo " ${percentual_virtual_uso}% da memoria virtual em uso ($virtualem_uso MB)")

        # Saída do script (como as informações são exibidas para o usuário)
        echo "***************************************************"
        echo "*** Monitor de consumo de memoria em tempo real ***"
        echo "***   Melhor visualizado em janela maximizada   ***"
        echo "***      Frequencia de atualizacao: $freq_atl seg.      ***"
        echo "***           Hora local: $(date +%r)           ***"
        echo "***************************************************"
        echo "***       Desenvolvido por Roger Principe       ***"
        echo "***************************************************"

        echo ""

        # Exibe as barras de consumo
        echo "MEMORIA RAM - TOTAL: $ramtotal MB"
        echo "${barra_ram}"
        echo ""
        echo "SWAP - TOTAL: $swaptotal MB"
        echo "$barra_swap"
        echo ""
        echo "MEMORIA VIRTUAL (RAM + SWAP) - TOTAL: $virtualtotal MB"
        echo "$barra_virtual"

        sleep $freq_atl
        clear
        done