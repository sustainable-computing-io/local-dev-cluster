From registry.access.redhat.com/ubi9

USER 0

WORKDIR /workspace

COPY . .
RUN yum update -y && yum install -y git sudo
#RUN yum install -y yum-utils
#RUN yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
#RUN yum install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin -y
RUN sudo ./main.sh containerruntime
RUN sudo ./verify.sh containerruntime