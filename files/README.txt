Drop binaries to distribute to lab devices in this folder.

Required:
  - MeshService64.exe   (server-keyed MeshCentral agent — copy from
                         ~/lab/meshcentral/meshcentral-data/signedagents/)

Optional:
  - SEB config files (.seb)
  - Any software installers you need to push

Anything placed here is served by 04_serve_files.sh on
http://<CONTROLLER_IP>:8080/ and is also pushable via Ansible's win_copy.

The MeshService64.exe binary has THIS server's URL and certificate fingerprint
baked into it. If the controller IP ever changes, MeshCentral regenerates the
file under signedagents/ on next start — re-copy it here.
