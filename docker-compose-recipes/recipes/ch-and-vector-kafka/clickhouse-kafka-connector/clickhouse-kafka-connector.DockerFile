FROM debian:latest

USER root

RUN apt-get update -y && apt-get install wget curl unzip default-jre -y

