vault plugin register -version=v0.13.0+ent database vault-plugin-database-oracle
vault secrets enable database

## ADD TO NESTOR'S ARTICLE HERE https://hashicorp.atlassian.net/wiki/spaces/VSE/pages/2485714945/Oracle+Database+Secrets+engine

podman pull container-registry.oracle.com/database/express:latest

podman run --rm --detach --name oraclexe -p 1521:1521 -p 5500:5500 -e ORACLE_PWD=your_secure_password container-registry.oracle.com/database/express:latest

# Get a shell
podman exec -it oraclexe /bin/bash
# IN THE ORACLE CONTAINER 
tee create_user.sql <<EOF
alter session set container=XEPDB1;
CREATE USER vault IDENTIFIED BY vaultpasswd;
ALTER USER vault DEFAULT TABLESPACE USERS QUOTA UNLIMITED ON USERS;
GRANT CREATE SESSION, RESOURCE , UNLIMITED TABLESPACE, DBA TO vault;
exit;
EOF
sqlplus sys/your_secure_password@XEPDB1 AS SYSDBA @create_user.sql
# END IN THE ORACLE CONTAINER


# Had to run the create script twice? Logged in manually in between :Shrug:
vault write database/roles/my-role \
    db_name=my-oracle-database \
    creation_statements='CREATE USER {{username}} IDENTIFIED BY "{{password}}"; GRANT CONNECT TO {{username}}; GRANT CREATE SESSION TO {{username}};' \
    default_ttl="1h" \
    max_ttl="24h"

vault write database/config/my-oracle-database \
     plugin_name=vault-plugin-database-oracle \
     connection_url="{{username}}/{{password}}@dev2-bastion.dev.azure.nick-philbrook.sbx.hashidemos.io:1521/XEPDB1" \
     username="vault" \
     password="vaultpasswd" \
     allowed_roles=my-role \
     max_connection_lifetime=60s

# Now request a dynamic credential
vault read database/creds/my-role

# to test inside the container:
sqlplus V_ROOT_MY_ROLE_VCJWCXMS9PG38W1/-Uu06biB-lkdzM3jjrNl@XEPDB1

# STATIC ROLE
# Get a shell
podman exec -it oraclexe /bin/bash
# IN THE ORACLE CONTAINER 
tee create_static_user.sql <<EOF
alter session set container=XEPDB1;
CREATE USER static IDENTIFIED BY vaultpasswd;
ALTER USER static DEFAULT TABLESPACE USERS QUOTA UNLIMITED ON USERS;
GRANT CREATE SESSION, RESOURCE , UNLIMITED TABLESPACE, DBA TO static;
exit;
EOF
sqlplus sys/your_secure_password@XEPDB1 AS SYSDBA @create_static_user.sql
# END IN THE ORACLE CONTAINER

# I did the rest of the static stuff in the UI because customer, but it was easy

# CLI for static
vault write database/config/oracle-static-database \
     plugin_name=vault-plugin-database-oracle \
     connection_url="{{username}}/{{password}}@dev2-bastion.dev.azure.nick-philbrook.sbx.hashidemos.io:1521/XEPDB1" \
     allowed_roles=my-static-role \
     self_managed=true

vault write database/static-roles/my-static-role \
    db_name=oracle-static-database \
    username="static" \
    password="vaultpasswd" \
    rotation_period="1h"
