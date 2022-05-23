# pull official base image
FROM node:14

# set working directory
WORKDIR /app


# install app dependencies
COPY package*.json ./

RUN yarn install 

# add app
COPY . ./

EXPOSE 3000

# start app
CMD ["yarn", "run", "start"]