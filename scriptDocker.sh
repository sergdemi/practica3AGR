#!/bin/bash


DOCKER_DIR="dockerP3"
mkdir -p $DOCKER_DIR/client/entrypoints
mkdir -p $DOCKER_DIR/router/entrypoints
mkdir -p $DOCKER_DIR/servidor



# Dockerfile para clientes
cat <<EOF > $DOCKER_DIR/client/Dockerfile_client
FROM ubuntu:22.04

# Run the command to install the required packages. This command adds a layer to the image.
RUN apt-get update && apt-get install -y iputils-ping && apt-get install -y iproute2 iptables
#the packet installed are the one util to add a route or ping a node.

COPY /entrypoints/ep_red1.sh /entrypoints/ep_red1.sh
COPY /entrypoints/ep_red2.sh /entrypoints/ep_red2.sh
COPY /entrypoints/ep_red3.sh /entrypoints/ep_red3.sh
COPY /entrypoints/ep_red4.sh /entrypoints/ep_red4.sh

#make the scripts executable 
RUN chmod +x /entrypoints/ep_red1.sh /entrypoints/ep_red2.sh /entrypoints/ep_red3.sh /entrypoints/ep_red4.sh



CMD ["/bin/bash"]
EOF



# Dockerfiles para routers
for i in 1 2 3 4
do

cat <<EOF > $DOCKER_DIR/client/entrypoints/ep_red$i.sh
#!/bin/bash

ip route change default via 10.0.$i.10


/bin/sleep infinity
EOF

cat <<EOF > $DOCKER_DIR/router/Dockerfile_router$i
FROM ubuntu:22.04

USER root
# Run the command to install the required packages
RUN apt-get update && apt-get install -y iputils-ping && apt-get install -y iproute2 coreutils iptables && apt-get install -y frr syslog-ng
#configure frr enabling daemon and setting ports
RUN sed -i 's/^bgpd_options=.*/bgpd_options="  --daemon -A 127.0.0.$i"/' /etc/frr/daemons && \
    sed -i 's/^zebra_options=.*/zebra_options=" -s 90000000 --daemon -A 127.0.0.$i"/' /etc/frr/daemons && \    
    sed -i 's/^bgpd=.*/zebra=yes\nbgpd=yes/' /etc/frr/daemons && sed -i 's/^ospfd=.*/ospfd=yes/' /etc/frr/daemons &&\
    sed -i 's/^zebra=.*/zebra=yes/' /etc/frr/daemons && \
    sed -i 's/^ospfd_options=.*/ospfd_options="  --daemon -A 127.0.0.$i"/' /etc/frr/daemons    
RUN echo "zebrasrv 2600/tcp" > /etc/services && echo "zebra 2601/tcp" >> /etc/services && echo "bgpd 2605/tcp" >> /etc/services \
    && echo "ospfd 2604/tcp" >> /etc/services
#allow ipforwarding
RUN sed -i 's/^#net.ipv4.ip_forward=1.*/net.ipv4.ip_forward=1/' /etc/sysctl.conf && \
    sed -i 's/^#net.ipv6.conf.all.forwarding=1.*/net.ipv6.conf.all.forwarding=1/' /etc/sysctl.conf && sysctl -p
#redirect syslog to fluentd node
RUN echo 'destination fluentdContainer { tcp("10.200.0.2" port(5140)); };\n' >> /etc/syslog-ng/syslog-ng.conf && \
    echo 'log { source(s_src); filter(f_syslog3); destination(fluentdContainer); };' >> /etc/syslog-ng/syslog-ng.conf


#add the entryscripts to the common image of the router

COPY entrypoints/ep_router$i.sh entrypoints/ep_router${i}.sh


#make the scripts executable 
RUN chmod +x /entrypoints/ep_router$i.sh 

CMD ["/bin/bash"]
EOF

done


# Entrypoints routers
cat <<EOF > $DOCKER_DIR/router/entrypoints/ep_router1.sh
#!/bin/bash

service syslog-ng start
service frr start

vtysh << EOS
conf t
log file /shared-volume/frr/frrRouter1.log
router ospf
network 10.100.0.0/24 area 0
network 10.1.0.0/24 area 0
end
EOS



/bin/sleep infinity
EOF

cat <<EOF > $DOCKER_DIR/router/entrypoints/ep_router2.sh
#!/bin/bash

service syslog-ng start
service frr start


vtysh << EOS
conf t
router ospf 
network 10.1.0.0/24 area 0
network 10.2.0.0/24 area 0
network 10.3.0.0/24 area 0
end
EOS




/bin/sleep infinity
EOF

cat <<EOF > $DOCKER_DIR/router/entrypoints/ep_router3.sh
#!/bin/bash

service syslog-ng start
service frr start


vtysh << EOS
conf t
router ospf 
network 10.2.0.0/24 area 0
network 10.0.1.0/24 area 0
network 10.0.2.0/24 area 0
end
EOS




/bin/sleep infinity
EOF

cat <<EOF > $DOCKER_DIR/router/entrypoints/ep_router4.sh
#!/bin/bash

service syslog-ng start
service frr start


vtysh << EOS
conf t
router ospf 
network 10.3.0.0/24 area 0
network 10.0.3.0/24 area 0
network 10.0.4.0/24 area 0
end
EOS




/bin/sleep infinity
EOF

# Dockerfile para servidor
cat <<EOF > $DOCKER_DIR/servidor/Dockerfile_servidor
FROM ubuntu:22.04

# Instalar paquetes necesarios: Node.js, npm, y git

RUN apt-get update && apt-get install -y iputils-ping && apt-get install -y iproute2 coreutils iptables nodejs npm git syslog-ng

# Clonar el repositorio del servidor web Node.js
RUN git clone https://github.com/gisai/SSR-master-server


WORKDIR /SSR-master-server
RUN npm install


EXPOSE 3000

CMD  [ "node", "app.js" ] 
EOF


# Crear archivo docker-compose.yml
cat <<EOF > $DOCKER_DIR/docker-compose.yml
version: '3'
services:

  servidor:    
    build: 
      context: ./servidor
      dockerfile: Dockerfile_servidor
    ports:
      - "3000:3000"
    cap_add:
      - NET_ADMIN  
    volumes:
      - ./professor-fluentd/shared-volume:/shared-volume    
    logging:
      driver: "fluentd"
      options:
        fluentd-address: 10.200.0.2:24224
        tag: servidor       
        fluentd-async: 'true'
    command: 
      - "/bin/sleep"
      - "infinity" 
    networks:
      red_servidor:
        ipv4_address: 10.100.0.2

  router1:    
    build: 
      context: ./router
      dockerfile: Dockerfile_router1
    entrypoint: entrypoints/ep_router1.sh    
    cap_add:
      - NET_ADMIN
    privileged: true
    volumes:
      - ./fluentd/shared-volume:/shared-volume   
    logging:
      driver: "fluentd"
      options:
        fluentd-address: 10.200.0.2:24224
        tag: router1  
        fluentd-async: 'true'   
    command: 
      - "/bin/sleep"
      - "infinity"
    networks:
      red_servidor:
        ipv4_address: 10.100.0.10
      red_r1-r2:
        ipv4_address: 10.1.0.10

  router2:    
    build: 
      context: ./router
      dockerfile: Dockerfile_router2
    entrypoint: entrypoints/ep_router2.sh    
    cap_add:
      - NET_ADMIN
    privileged: true
    volumes:
      - ./fluentd/shared-volume:/shared-volume   
    logging:
      driver: "fluentd"
      options:
        fluentd-address: 10.200.0.2:24224
        tag: router2

        fluentd-async: 'true'
    command: 
      - "/bin/sleep"
      - "infinity"
    networks:      
      red_r1-r2: 
        ipv4_address: 10.1.0.20
      red_r2-r3:
        ipv4_address: 10.2.0.10
      red_r2-r4:
        ipv4_address: 10.3.0.10

  router3:    
    build: 
      context: ./router
      dockerfile: Dockerfile_router3
    entrypoint: entrypoints/ep_router3.sh    
    cap_add:
      - NET_ADMIN
    privileged: true  
    volumes:
      - ./fluentd/shared-volume:/shared-volume  
    logging:
      driver: "fluentd"
      options:
        fluentd-address: 10.200.0.2:24224
        tag: router3       
        fluentd-async: 'true'  
    command: 
      - "/bin/sleep"
      - "infinity"
    networks:      
      red_r2-r3: 
        ipv4_address: 10.2.0.20
      red_r3-red1:
        ipv4_address: 10.0.1.10
      red_r3-red2:
        ipv4_address: 10.0.2.10

  router4:    
    build: 
      context: ./router
      dockerfile: Dockerfile_router4
    entrypoint: entrypoints/ep_router4.sh    
    cap_add:
      - NET_ADMIN
    privileged: true
    volumes:
      - ./fluentd/shared-volume:/shared-volume    
    logging:
      driver: "fluentd"
      options:
        fluentd-address: 10.200.0.2:24224
        tag: router4
        fluentd-async: 'true'
    command: 
      - "/bin/sleep"
      - "infinity"
    networks:      
      red_r2-r4: 
        ipv4_address: 10.3.0.20
      red_r4-red3:
        ipv4_address: 10.0.3.10
      red_r4-red4:
        ipv4_address: 10.0.4.10

  sw_red1:
    build: 
      context: ./client
      dockerfile: Dockerfile_client
    entrypoint: entrypoints/ep_red1.sh    
    cap_add:
      - NET_ADMIN
    depends_on:
      - router3  
    command: 
      - "/bin/sleep"
      - "infinity" 
    networks:      
      red_r3-red1:
        ipv4_address: 10.0.1.20

  sw_red2:
    build: 
      context: ./client
      dockerfile: Dockerfile_client
    entrypoint: entrypoints/ep_red2.sh
    cap_add:
      - NET_ADMIN
    depends_on:
      - router3
    command: 
      - "/bin/sleep"
      - "infinity"  
    networks:      
      red_r3-red2:
        ipv4_address: 10.0.2.20

  sw_red3:
    build: 
      context: ./client
      dockerfile: Dockerfile_client
    entrypoint: entrypoints/ep_red3.sh   
    cap_add:
      - NET_ADMIN
    depends_on:
      - router4
    command: 
      - "/bin/sleep"
      - "infinity"  
    networks:      
      red_r4-red3:
        ipv4_address: 10.0.3.20

  sw_red4:
    build: 
      context: ./client
      dockerfile: Dockerfile_client
    entrypoint: entrypoints/ep_red3.sh  
    cap_add:
      - NET_ADMIN
    depends_on:
      - router4
    command: 
      - "/bin/sleep"
      - "infinity"  
    networks:      
      red_r4-red4:
        ipv4_address: 10.0.4.20

networks:
  red_servidor:
    driver: bridge
    ipam:
      config:
        - subnet: 10.100.0.0/24
  red_r1-r2:
    driver: bridge
    ipam:
      config:
        - subnet: 10.1.0.0/24
  red_r2-r3:
    driver: bridge
    ipam:
      config:
        - subnet: 10.2.0.0/24
  red_r2-r4:
    driver: bridge
    ipam:
      config:
        - subnet: 10.3.0.0/24
  red_r3-red1:
    driver: bridge
    ipam:
      config:
        - subnet: 10.0.1.0/24
  red_r3-red2:
    driver: bridge
    ipam:
      config:
        - subnet: 10.0.2.0/24
  red_r4-red3:
    driver: bridge
    ipam:
      config:
        - subnet: 10.0.3.0/24
  red_r4-red4:
    driver: bridge
    ipam:
      config:
        - subnet: 10.0.4.0/24
EOF



# Desplegar la red utilizando docker-compose
echo "Desplegando red con Docker Compose..."
docker-compose -f $DOCKER_DIR/docker-compose.yml up -d

echo "Red desplegada con éxito."
