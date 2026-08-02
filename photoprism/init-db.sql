CREATE DATABASE IF NOT EXISTS photoprism_personal;
CREATE DATABASE IF NOT EXISTS photoprism_compartido;
GRANT ALL PRIVILEGES ON photoprism_personal.* TO 'photoprism'@'%';
GRANT ALL PRIVILEGES ON photoprism_compartido.* TO 'photoprism'@'%';
FLUSH PRIVILEGES;
