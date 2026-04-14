---
all:
  vars:
    ansible_user: student
    ansible_ssh_private_key_file: ~/.ssh/hkhk_lab
    ansible_python_interpreter: /usr/bin/python3
  children:
    osalejad:
      hosts:
%{ for name in osalejad ~}
        mon-${name}:
          ansible_host: 192.168.100.${osaleja_ip_start + index(osalejad, name)}
%{ endfor ~}
    targets:
      hosts:
        mon-target:
          ansible_host: 192.168.100.${target_ip}
        mon-target-web:
          ansible_host: 192.168.100.${target_web_ip}
