-- https://www.digitalocean.com/community/tutorials/how-to-set-up-mysql-master-master-replication
SLAVE stop; 
--
CHANGE MASTER TO
       MASTER_HOST = '10.0.4.1', 
       MASTER_USER = 'replicator',
       MASTER_PASSWORD = 'RL0KM98sbdwRpUh3C433pgURIsv0vL2IyK5Crrnd',
       MASTER_LOG_FILE = 'mysql-bin.000001',
       MASTER_LOG_POS = 107; 
--
SLAVE start; 
