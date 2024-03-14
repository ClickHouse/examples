# Does not need to have access to any pipeline code.

FROM python:3.11-slim


ENV DAGSTER_HOME=/opt/dagster/dagster_home/
RUN mkdir -p $DAGSTER_HOME
WORKDIR $DAGSTER_HOME

COPY dagster $DAGSTER_HOME

# how to download pip packets to speed up "docker up":
# make sh
# edit requirements.txt
# cd deps && pip download -r ../requirements.txt

#COPY dependencies $DAGSTER_HOME/dependencies
RUN pip install -r requirements.txt 
#--no-index --find-links=dependencies/

ENTRYPOINT ["dagster","dev","-h","0.0.0.0","-p","3000","-m","user_code"]
