# About

```
# Create a stack.
./deploy.rb branch_name
```

Soon there will be `production` branch and deploying it is a special case.

# Deploying a stack

```
docker push tutum.co/yniche/yniche.com:vincent-meeting
docker build -t tutum.co/yniche/yniche.com:vincent-meeting ..
# Not necessary like that, just tagging an existing Tutum image somehow would do. As long as the tag is present on Tutum, it works.
# No need for a separate branch either.
```

From here on all you have to do is to rebuild the image and push it to Tutum. Since we're using the `autoredeploy` feature, the service will be redeployed automatically.
