# Use an official Node.js runtime as a parent image
FROM node:18

# Set the working directory in the container
WORKDIR /app

# Copy the package.json and package-lock.json files to the working directory
COPY package*.json ./

# Install dependencies
RUN npm install

# Copy the rest of the application code to the working directory
COPY . .

# Set environment variables
ENV HOST=109.199.114.52
ENV PORT=9596

# Expose the port the app runs on
EXPOSE 9596

# Command to run your application
CMD ["npm", "start"]
