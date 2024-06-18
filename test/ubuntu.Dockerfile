From ubuntu

WORKDIR /workspace

COPY . .
RUN apt-get update -y && apt-get install -y git sudo
RUN ./main.sh containerruntime
RUN ./verify.sh containerruntime
