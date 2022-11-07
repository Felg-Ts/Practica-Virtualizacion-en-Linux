#!/bin/bash

#Funcion para pausar el script
pause(){
	read -p "Presiona [Enter] para continuar..." fackEnterKey
}

#Creacion imagen base
if [[ `virsh vol-list --pool default | egrep -Eo "bullseye-base.qcow2$"` == "bullseye-base.qcow2" ]]; then
    echo "La imagen base a sido copiada anteriormente"

else
    if
        echo "Copiando imagen-base"
        cp bullseye-base.qcow2 /var/lib/libvirt/images/
    then
        virsh -c qemu:///system pool-refresh default >> /dev/null
        echo "imagen-base copiada"
    else
        echo "Error al copiar la imagen"
    fi
fi

#Creacion de volumen a partir de imagen-base
if [[ `virsh vol-list --pool default | egrep -Eo 'maquina1.qcow2$'` == "maquina1.qcow2" ]]; then
    echo "Ya existe la imagen maquina1.qcow"

else
    if
        echo "Creando imagen maquina1"
        virsh -c qemu:///system vol-create-as default maquina1.qcow2 5G --format qcow2 --backing-vol bullseye-base.qcow2 --backing-vol-format qcow2 >> /dev/null
    then
        echo "imagen maquina1 creada"
    else
        echo "Error al crear la imagen"
    fi
fi

#Creacion y activacion red intra
if [[ `virsh net-list | egrep -Eo 'intra'` == "intra" ]]; then
    echo "Ya existe la red intra"

else
    if
        echo "Creando la red intra"
        virsh -c qemu:///system net-define red-nat.xml >> /dev/null
    then
        virsh -c qemu:///system net-start intra >> /dev/null
        virsh -c qemu:///system net-autostart intra >> /dev/null
        echo "Red intra creada"
    else
        echo "Error al crear la red intra"
    fi
fi

#Creacion vm maquina1
if [[ `virsh list --all | egrep -Eo 'maquina1'` == "maquina1" ]]; then
    echo "maquina1 ya existe"

else
    if
        echo "Creando la vm maquina1"
        virt-install --connect qemu:///system --name maquina1 --memory 1024 --vcpus=2 --disk path=/var/lib/libvirt/images/maquina1.qcow2 --network network=intra --os-type linux --boot hd --os-variant=debian10 --vnc --noautoconsole --hvm --keymap es >> /dev/null
    then
        virsh -c qemu:///system autostart maquina1>> /dev/null
        echo "vm maquina1 creada"
    else
        echo "Error al crear la vm maquina1"
        exit
    fi
fi

#Creacion volumen adicional vol1.raw
if [[ `virsh vol-list --pool default | egrep -Eo 'vol1.raw$'` == "vol1.raw" ]]; then
    echo "El volumen vol1.raw ya existe"

else
    if
        echo "Creando el volumen vol1.raw"
        virsh -c qemu:///system vol-create-as default vol1.raw --format raw 1G >> /dev/null
    then
        virsh -c qemu:///system attach-disk maquina1 /var/lib/libvirt/images/vol1.raw vdb --driver=qemu --type disk --subdriver raw --persistent >> /dev/null
        echo "El volumen vol1.raw a sido creado y asignado a la vm maquina1"
    else
        echo "Error al crear vol1.raw"
        exit
    fi
fi

sleep 30

#Ip de la vm para ejecutar comandos por ssh
ip=$(virsh -c qemu:///system domifaddr maquina1 | grep -Eo '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}') >> /dev/null


#Creacion y montaje de directorio html
if [[ `ssh -oStrictHostKeyChecking=no -i id_rsa -t debian@$ip "sudo ls /var/www/ | grep -Eo 'html'"` == 'html' ]]; then
    echo "El directorio html ya existe en maquina1"

else
    if
        echo "Creando el directorio html"
        ssh -oStrictHostKeyChecking=no -i id_rsa -t debian@$ip "sudo mkdir -p /var/www/html && sudo mkfs.xfs /dev/vdb" >> /dev/null
        ssh -oStrictHostKeyChecking=no -i id_rsa -t debian@$ip "sudo mount /dev/vdb /var/www/html" >> /dev/null
    then
        echo "El directorio html a sido creado y asignado al disco vdb"
    else
        echo "Error durante la creación del directorio html"
        exit
    fi
fi

#Instalacion apache2 y copia de index
if [[ `ssh -oStrictHostKeyChecking=no -i id_rsa -t debian@$ip "ls /etc | egrep -Eo 'apache2'"` == 'apache2' ]]; then
    echo "apache2 está instalado en maquina1"

else
    if
        echo "Instalando apache2"
        ssh -oStrictHostKeyChecking=no -i id_rsa -t debian@$ip "sudo apt install apache2 -y" >> /dev/null
        ssh -oStrictHostKeyChecking=no -i id_rsa -t debian@$ip "sudo mv /home/debian/index.html /var/www/html" >> /dev/null
    then
        scp -i id_rsa index.html debian@$ip:/home/debian >> /dev/null
        echo "Apache a sido instalado"
    else
        echo "Error durante la instalación de apache"
        exit
    fi
fi

#Ver ip de la maquina1
virsh domifaddr maquina1

#Pausa del script
pause

#Instalacion de lxc y creacion de contenedor
if [[ `ssh -oStrictHostKeyChecking=no -i id_rsa -t debian@$ip "ls /usr/bin/ | egrep -Eo 'lxc-ls'"` != 'lxc-ls' ]]; then
    if
        echo "Instalando lxc"
        ssh -oStrictHostKeyChecking=no -i id_rsa -t debian@$ip "sudo apt install lxc -y" >> /dev/null
    then
        echo "lxc a sido instalado"
        echo "Creando container1"
        ssh -oStrictHostKeyChecking=no -i id_rsa -t debian@$ip "sudo lxc-create -n container1 -t debian -- -r bullseye" >> /dev/null
        echo "container1 a sido creado"
    else
        echo "Error durante la instalación de lxc"
    fi
else
    echo "lxc está instalado en maquina1"
    if [[ `ssh -oStrictHostKeyChecking=no -i id_rsa -t debian@$ip "sudo lxc-ls | egrep -Eo 'container1'"` == 'container1' ]]; then
        echo "Ya existe el conetenedor container1"
    else
        echo "Creando container1"
        ssh -oStrictHostKeyChecking=no -i id_rsa -t debian@$ip "sudo lxc-create -n container1 -t debian -- -r bullseye" >> /dev/null
        echo "Container1 a sido creado"
    fi
    
fi

virsh shutdown maquina1 >> /dev/null

sleep 15

#Interfaz puente para maquina1
if [[ `virsh domiflist maquina1 | egrep -Eo 'bridge'` == "bridge" ]]; then
    echo "La maquina1 ya tiene una interfaz bridge"

else
    if
        echo "Añadiendo interfaz bridge a maquina1"
        virsh -c qemu:///system attach-interface maquina1 bridge br0 --model virtio --persistent
    then
        echo "La interfaz bridge a sido añadida a maquina1"
    else
        echo "Error al añadir la intefaz bridge"
    fi

fi

virsh start maquina1 >> /dev/null

sleep 35

ssh -oStrictHostKeyChecking=no -i id_rsa -t debian@$ip "ip a show eth1 | grep -Eo '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/24'"

virsh shutdown maquina1 >> /dev/null

sleep 20

#Aumentar memoria a 2G a maquina1
virt-xml maquina1 --edit --memory memory=2048,currentMemory=2048 >> /dev/null

virsh -c qemu:///system detach-disk maquina1 vdb --persistent >> /dev/null

#Creacion de snapshot de maquina1
if [[ `virsh -c qemu:///system snapshot-list maquina1 | egrep -Eo 'snapshot1'` == "snapshot1" ]]; then
    echo "snapshot1 ya existe en maquina1"

else
    if
        echo "Creando la snapshot1 en maquina1"
        virsh -c qemu:///system snapshot-create-as maquina1 --name snapshot1 --description "Primera snapshot" --atomic >> /dev/null
    then
        virsh start maquina1 >> /dev/null
        #sleep 20
        #ssh -oStrictHostKeyChecking=no -i id_rsa -t debian@$ip "sudo mount /dev/vdb /var/www/html" 
        echo "snapshot1 creada"
        virsh -c qemu:///system attach-disk maquina1 /var/lib/libvirt/images/vol1.raw vdb --driver=qemu --type disk --subdriver raw --persistent >> /dev/null
    else
        echo "Error al crear la snapshot"
        virsh -c qemu:///system attach-disk maquina1 /var/lib/libvirt/images/vol1.raw vdb --driver=qemu --type disk --subdriver raw --persistent >> /dev/null
    fi
fi
