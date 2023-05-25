# Choose ubuntu version
FROM mcr.microsoft.com/mssql/server:2022-latest

# Create app directory
WORKDIR /usr/src/app

# Copy initialization scripts
COPY --chown=mssql . /usr/src/app

USER root
# Install unzip
RUN apt-get update && apt-get install -y unzip
RUN chown -R mssql /tmp
USER mssql
# Set environment variables, not have to write them with the docker run command
# Note: make sure that your password matches what is in the run-initialization script 
ENV MSSQL_SA_PASSWORD mssqlpassword_123
ENV ACCEPT_EULA Y

# Expose port 1433 in case accessing from other container
# Expose port externally from docker-compose.yml
EXPOSE 1433

RUN ls -alrth /usr/src/app

# Run Microsoft SQL Server and initialization script (at the same time)
ENTRYPOINT [ "/bin/bash", "entrypoint.sh" ]
CMD [ "/opt/mssql/bin/sqlservr" ]
