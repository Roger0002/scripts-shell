#!/usr/bin/env bash

# Script gerador de relação de discos em clusters Oracle
# O objetivo desse script é ser utilizado em um servidor que tem acesso ao(s) servidor(es) de banco de dados Oracle, com relação de confiança
# Esse script conecta nos servidores e gera o relatório de todos os discos que o banco utiliza, considerando todos os servidores do ambiente, se houver mais de um
# Desenvolvido por Roger Príncipe (roger@principe.eti.br)

clear
echo
echo "######################################################################"
echo "### SCRIPT GERADOR DE RELATORIO DE DISCOS - BANCOS DE DADOS ORACLE ###"
echo "######################################################################"
echo
echo " 1) Ambiente A (hostnamea/hostnameb);"
echo " 2) Ambiente B (hostnamec/hostnamed);"
echo " 3) Ambiente C (hostnamee/hostnamef);"
echo
read -p "Digite o código do ambiente: " opc

case $opc in
"1")    echo -e "hostnamea\nhostnameb" > lista_servidores ;;
"2")    echo -e "hostnamec\nhostnamed" > lista_servidores ;;
"3")    echo -e "hostnamee\nhostnamef" > lista_servidores ;;
*)      echo "Opção inválida"
        exit ;;
esac
clear

SERVIDORES=`cat lista_servidores`
CTRL_MULTIPATHING="?"
ARQ_DESPEJO="/tmp/saida_script_devices_oracle_$(date +%s).tmp"
temhdlm=`ssh -q $(echo "$SERVIDORES" | head -n 1) "rpm -q HDLM > /dev/null 2>&1; echo \\$?"`
tempp=`ssh -q $(echo "$SERVIDORES" | head -n 1) "rpm -q EMCpower.LINUX > /dev/null 2>&1; echo \\$?"`

if [ "$temhdlm" -eq 0 -a "$tempp" -ne 0 ]; then
        CTRL_MULTIPATHING="HDLM"
fi

if [ "$temhdlm" -ne 0 -a "$tempp" -eq 0 ]; then
        CTRL_MULTIPATHING="PP"
fi

if [ "$CTRL_MULTIPATHING" == "?" ]; then
        echo -e "\n====================================================\nProblema na definição do contralador de multipathing.\nContacte o administrador do script e relate o erro.\n============== roger@principe.eti.br ===============\n"
        exit 1
fi

DIRETORIO_DEVICES_BANCO="/dev/oracleasm/disks"

function grepp(){
# Uso: Exatamente como o grep -p do AIX, mas se aplica apenas à pesquisa de devices na saida do comando "powermt display dev=all", do EMC PowerPath
awk --re-interval /\(WWN=\|e\ ID=\)$1[[:cntrl:]\ ]/ RS="\n\n" ORS="\n\n"
}

# Construindo a lista de LUNs
pos=1
for servidor in $SERVIDORES; do
        if [ "$pos" -eq 1 ]; then
                [[ "$CTRL_MULTIPATHING" == "PP" ]] && ssh -q $servidor "powermt display dev=all | grep 'Logical device ID' | cut -d '=' -f 2 | cut -d ' ' -f 1" > /tmp/lista_luns.tmp
                [[ "$CTRL_MULTIPATHING" == "HDLM" ]] && ssh -q $servidor "dlnkmgr view -lu | grep -P sddl[a-z]{2} | awk '{print \$1}'" > /tmp/lista_luns.tmp
                pos=$(($pos+1))
        else
                [[ "$CTRL_MULTIPATHING" == "PP" ]] && ssh -q $servidor "powermt display dev=all | grep 'Logical device ID' | cut -d '=' -f 2 | cut -d ' ' -f 1" >> /tmp/lista_luns.tmp
                [[ "$CTRL_MULTIPATHING" == "HDLM" ]] && ssh -q $servidor "dlnkmgr view -lu | grep -P sddl[a-z]{2} | awk '{print \$1}'" >> /tmp/lista_luns.tmp
        fi
        sort -u /tmp/lista_luns.tmp > lista_luns.txt
done

LISTA_DISCOS=`cat lista_luns.txt`

function descobrir_device_bd(){
# Uso: Chamar a função passando o LUN ID como parâmetro
# Essa função deve devolver o device utilizado pelo Oracle
[[ "$CTRL_MULTIPATHING" == "PP" ]] && disco_so_temp=`ssh -q $(echo "$SERVIDORES" | head -n 1) "powermt display dev=all" | grepp $1 | grep 'Pseudo name=' | cut -d '=' -f 2 | cut -d " " -f 1`
[[ "$CTRL_MULTIPATHING" == "HDLM" ]] && disco_so_temp=`ssh -q $(echo "$SERVIDORES" | head -n 1) "dlnkmgr view -lu" | grep -P sddl[a-z]{2} | grep $1 | awk '{print $2}'`
mm=`descobrir_mm $(echo "$SERVIDORES" | head -n 1) $disco_so_temp`
ssh -q $(echo "$SERVIDORES" | head -n 1) "if [ -d /dev/raw/ ]; then
        for rawdev in \$(find /dev/raw/ -regextype posix-egrep -regex /dev/raw/raw[0-9]+); do
                raw -q \$rawdev | sed 's/[:,]//g' | awk '{print \" \"\$(NF-2)\", \"\$NF\" \"\$1}' | sed 's/\/dev\/raw\///'
        done > /tmp/raw_list.tmp
fi"
disco_bd=$(ssh -q `echo "$SERVIDORES" | head -n 1` "(ls -l $DIRETORIO_DEVICES_BANCO 2> /dev/null; cat /tmp/raw_list.tmp 2> /dev/null)" | tr -s " " | sed 's/, /,/g' | grep " $mm " | awk '{print $NF}')
if [ ! -z "$disco_bd" ]; then
        echo $disco_bd
else
        echo "---------"
fi
rm -f /tmp/raw_list.tmp
}

function descobrir_device_so(){
# Uso: Chamar a função passando o servidor e o Lun ID como parâmetros, respectivamente
# Essa função devolve qual é o device do SO (sem o /dev/)
[[ "$CTRL_MULTIPATHING" == "PP" ]] && disco_so_temp=$(ssh -q $1 "powermt display dev=all" | grepp $2 | grep 'Pseudo name=' | cut -d '=' -f 2 | cut -d " " -f 1)
[[ "$CTRL_MULTIPATHING" == "HDLM" ]] && disco_so_temp=$(ssh -q $1 "dlnkmgr view -lu" | grep -P sddl[a-z]{2} | grep -P ^$2 | awk '{print $2}')
if [ ! -z "$disco_so_temp" ]; then
        echo $disco_so_temp
else
        echo "---------"
fi
}

function descobrir_particao_bool(){
# Uso: Chamar a função passando o servidor e o device do SO como parâmetros, respectivamente
# Essa função devolve 0 (se o disco está particionado) ou 1 (se não está)
exit_code=`ssh -q $1 "ls -l /dev/${2}1 > /dev/null 2>&1; echo \$?"`
if [ "$exit_code" -ne 0 ]; then
        exit_code=1
fi
echo $exit_code
}

function descobrir_mm(){
# Uso: Chamar a função passando o servidor e o device do SO como parâmetros, respectivamente
# Essa função devolve o major e o minor number do device do SO (disco ou partição) no formato "min_num,maj_num,"
# Exemplo: 120,1521
if [ "$device_particionado" -eq 0 ]; then
        ssh -q $1 "ls -l /dev/${2}1 2> /dev/null" | tr -s " " | sed 's/, /,/g' | awk -F'[ ,]' '{print $5","$6}'
else
        ssh -q $1 "ls -l /dev/$2" | tr -s " " | sed 's/, /,/g' | awk -F'[ ,]' '{print $5","$6}'
fi
}

echo -e "Gerando o relatório. Por favor, aguarde..."

(echo -ne "LUN_ID DEVICE_ORACLE "
for servidor in $SERVIDORES; do
        echo -ne "$servidor "
done
echo
for disco in $LISTA_DISCOS; do
        device_particionado=$(descobrir_particao_bool `echo "$SERVIDORES" | head -n 1` $disco)
        echo -ne "$disco $(descobrir_device_bd $disco) "
        for servidor in $SERVIDORES; do
                echo -ne "`descobrir_device_so $servidor $disco` "
        done
        echo
done) | column -t > $ARQ_DESPEJO
clear
cat $ARQ_DESPEJO

rm -f lista_luns.txt lista_servidores $ARQ_DESPEJO
