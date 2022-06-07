sudo docker run --name kerberos-camera1 \
-p 80:80 -p 8889:8889 \
-v /mnt/hdd/kerberosio/config:/etc/opt/kerberosio/config \
-v /mnt/hdd/kerberosio/capture:/etc/opt/kerberosio/capture \
-v /mnt/hdd/kerberosio/logs:/etc/opt/kerberosio/logs \
-v /mnt/hdd/kerberosio/webconfig:/var/www/web/config \
-d kerberos/kerberos
