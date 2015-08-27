tutum stack up --name=staging-services -f staging.services.yml

# About

This is a deployment solution for deploying similar stacks of services on Tutum.
It has been designed for deploying feature branches on staging. So for instance,
let's say we created an `auth0` branch and implemented `auth0` in there. It got
stable enough and now we want to deploy it to `auth0.staging.yniche.com`. So we
do `./deploy.rb auth0` which will:

- Create, deploy and a new stack `yniche-auth0`.
-

./deploy.rb auth0 auth0

```
# Create a stack.
./deploy.rb stack_name
```

Soon there will be `production` branch and deploying it is a special case.

# Caveats

If you just want to redeploy the code, all you have to do is to push the Docker
image and it will be automatically redeployed. You only have to use this script
for the initial branch deployment and then if anything in the infrastructure
changes.

# Discussion: Staging vs. production

## -One Tutum account, pushing to Dockerhub, autoredeploy trigger-

**Pros:**

**Cons:** Devs can't deploy new stacks! We could use only one private Dockerhub
repo, then pay. So far we only need one for `api.yniche.com`, `yniche.com` image
contains only the compiled source.

## Two Tutum accounts

**Pros:** Solid security. Devs can fiddle with the staging account, deploy and
redeploy stacks as they wish.

**Cons:** It needs something like:

How would CD to production work:
There would be a tiny service deployed to production Tutum that would be registered
as a GH post-receive webhook URL, watching for changes on the 'production' branch.

Could also just be credentials to CircleCI, as long as no one could read them,
but I don't think that's possible.

# Deploying a stack

```
docker push tutum.co/yniche/yniche.com:vincent-meeting
docker build -t tutum.co/yniche/yniche.com:vincent-meeting ..
# Not necessary like that, just tagging an existing Tutum image somehow would do.
As long as the tag is present on Tutum, it works.
# No need for a separate branch either.
```

From here on all you have to do is to rebuild the image and push it to Tutum.
Since we're using the `autoredeploy` feature, the service will be redeployed
automatically.
