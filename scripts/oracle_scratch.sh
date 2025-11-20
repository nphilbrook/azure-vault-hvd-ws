vault plugin register -version=v0.13.0+ent database vault-plugin-database-oracle

## ADD TO NESTOR'S ARTICLE

podman pull container-registry.oracle.com/database/express:latest

podman run   --rm    --detach       --name oraclexe       -p 1521:1521       -p 5500:5500       -e ORACLE_PWD=your_secure_password    container-registry.oracle.com/database/express:latest


# Had to run the create script twice? Logged in manually in between :Shrug:
vault write database/roles/my-role \
    db_name=my-oracle-database \
    creation_statements='CREATE USER {{username}} IDENTIFIED BY "{{password}}"; GRANT CONNECT TO {{username}}; GRANT CREATE SESSION TO {{username}};' \
    default_ttl="1h" \
    max_ttl="24h"

vault write database/config/my-oracle-database \
     plugin_name=vault-plugin-database-oracle \
     connection_url="{{username}}/{{password}}@dev-bastion.ysaddc5oq3cebc2m2idinljkia.gx.internal.cloudapp.net:1521/XEPDB1" \
     username="vault" \
     password="vaultpasswd" \
     allowed_roles=my-role \
     max_connection_lifetime=60s    

# to test inside the container:
sqlplus V_ROOT_MY_ROLE_VCJWCXMS9PG38W1/-Uu06biB-lkdzM3jjrNl@XEPDB1
