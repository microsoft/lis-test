#!/bin/bash

logger "Installing LAMP + WordPress"
distro="$(head -1 /etc/issue)"

git clone https://github.com/WordPress/WordPress
curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
chmod +x wp-cli.phar
sudo mv wp-cli.phar /usr/local/bin/wp
wget https://ciwestusv2.blob.core.windows.net/scripts/wltest.jpg


if [[ ${distro} == *"Ubuntu"* ]]
then
	sudo apt-get -y update
	# Install the LAMP stack
	# Set up a silent install of MySQL
	sudo bash -c 'export DEBIAN_FRONTEND=noninteractive;apt-get install -y mysql-server'
	if [ $? -ne 0 ]; then
		echo -e "Failed to install mysql,please check installation logs"
		exit 1
	fi
	sudo apt-get -y install nginx php-fpm php-mysql php-gd
	if [ $? -ne 0 ]; then
		echo -e "Failed to install package,please check installation logs"
		exit 1
	fi
	# Create a MySQL Database and User for WordPress
	sudo mysql -u root -e "CREATE DATABASE wordpress DEFAULT CHARACTER SET utf8 COLLATE utf8_unicode_ci;"
	sudo mysql -u root -e "GRANT ALL ON wordpress.* TO 'wordpressuser'@'localhost' IDENTIFIED BY 'p@ssw0rd0507';"
	sudo mysql -u root -e "FLUSH PRIVILEGES;"

    echo 'cgi.fix_pathinfo=0'| sudo tee -a /etc/php/7.0/fpm/php.ini	

	#Configure Nginx to Use the PHP Processor
    sudo sed -i s'/^/#/' /etc/nginx/sites-available/default
	echo | sudo tee -a /etc/nginx/sites-available/default << EOF
server {
    listen 80 default_server;
    listen [::]:80 default_server;

    root /var/www/html;
    index index.php index.html index.htm index.nginx-debian.html;

    server_name $1;

    location / {
        try_files \$uri \$uri/ =404;
    }

    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php7.0-fpm.sock;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOF

    sudo systemctl reload nginx

	#Download and configure wordpress
	sudo cp -a WordPress/. /var/www/html

	sudo wp core config --dbhost=127.0.0.1 --dbname=wordpress --dbuser=wordpressuser --dbpass=p@ssw0rd0507 --allow-root --path='/var/www/html' 
	sudo wp core install --url=http://$1 --title="My Test WordPress" --admin_name=wordpress_admin --admin_password='4Long&Strong1' --admin_email=you@example.com --allow-root --path='/var/www/html' 

	imageID=$(sudo wp media import ./wltest.jpg --porcelain --allow-root --path='/var/www/html')
	imageLINK=$(wp db query "SELECT guid FROM wp_posts WHERE ID='$imageID'" --silent --skip-column-names --allow-root --path='/var/www/html')
	echo $imageLINK
	postID=`wp post create --post_title="workloadtest" --post_status=publish --post_content="<a href=""$imageLINK""><img class=""size-full"" src=""$imageLINK"" /></a>" --allow-root --path='/var/www/html'`
	echo $postID

	# Restart nginx
	sudo systemctl stop nginx
	sleep 30
	sudo systemctl start nginx
	sleep 30


elif [[ ${distro} == *"Amazon"* ]]
then
	sudo yum -y install mysql-server nginx php php-mysql php-fpm php-gd
	sudo service mysqld start
	sudo service nginx start
	# Create a MySQL Database and User for WordPress
	sudo mysql -u root -e "CREATE DATABASE wordpress DEFAULT CHARACTER SET utf8 COLLATE utf8_unicode_ci;"
	sudo mysql -u root -e "GRANT ALL ON wordpress.* TO 'wordpressuser'@'localhost' IDENTIFIED BY 'p@ssw0rd0507';"
	sudo mysql -u root -e "FLUSH PRIVILEGES;"

    #Configure the PHP Processor
    echo 'cgi.fix_pathinfo=0'| sudo tee -a /etc/php.ini
    sudo sed -i s'/listen =/;listen =/' /etc/php-fpm.d/www.conf
	echo | sudo tee -a /etc/php-fpm.d/www.conf << EOF
listen = /var/run/php-fpm/php-fpm.sock
listen.owner = nobody
listen.group = nobody
listen.mode = 0666
EOF
    sudo sed -i s'/user = apache/user = nginx/' /etc/php-fpm.d/www.conf
    sudo sed -i s'/group = apache/group = nginx/' /etc/php-fpm.d/www.conf
    sudo service php-fpm start

    #Configure Nginx to Process PHP Pages
    sudo sed -i '/^http {/a\    server_names_hash_bucket_size 128;' /etc/nginx/nginx.conf
    echo | sudo tee -a /etc/nginx/conf.d/default.conf << EOF
server {
    listen       80;
    server_name  $1;

    # note that these lines are originally from the "location /" block
    root   /usr/share/nginx/html;
    index index.php index.html index.htm;

    location / {
        try_files \$uri \$uri/ =404;
    }
    error_page 404 /404.html;
    error_page 500 502 503 504 /50x.html;
    location = /50x.html {
        root /usr/share/nginx/html;
    }

    location ~ \.php$ {
        try_files \$uri =404;
        fastcgi_pass unix:/var/run/php-fpm/php-fpm.sock;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
    }
}
EOF

	sudo cp -a WordPress/. /usr/share/nginx/html
	wp core config --dbhost=127.0.0.1 --dbname=wordpress --dbuser=wordpressuser --dbpass=p@ssw0rd0507 --allow-root --path='/usr/share/nginx/html' 
	wp core install --url=http://$1 --title="My Test WordPress" --admin_name=wordpress_admin --admin_password='4Long&Strong1' --admin_email=you@example.com --allow-root --path='/usr/share/nginx/html' 

	imageID=$(wp media import ./wltest.jpg --porcelain --allow-root --path='/usr/share/nginx/html')
	imageLINK=$(wp db query "SELECT guid FROM wp_posts WHERE ID='$imageID'" --silent --skip-column-names --allow-root --path='/usr/share/nginx/html')
	postID=`wp post create --post_title="workloadtest" --post_status=publish --post_content="<a href=""$imageLINK""><img class=""size-full"" src=""$imageLINK"" /></a>" --allow-root --path='/usr/share/nginx/html'`

	# Restart nginx
	sudo service nginx stop
	sleep 30
	sudo service nginx start
	sleep 30
fi


echo "PHP Version: `php -v`"
echo "MySQL Version: `mysql -V`"
wget --spider -q -o /dev/null  --tries=1 -T 5 http://$1/?p=4
if [ $? -eq 0 ]; then
    echo -e "http://$1/?p=4 is reachable!"
else
    echo -e "Error: http://$1/?p=4 is unreachable!"
    exit 1
fi
