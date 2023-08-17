# This is the default section.  The "default" keyword (section) lets
# you set default values for other keywords globally.  The default
# values can be overridden at different parts of the pipeline when
# needed.
#
default:
  tags:
    - unity
    - shell


# This piepline has four stages
#
stages:
  - build
  - test
  - push
  - deploy



# None of the following jobs are using "tags" keyword because the
# default "tags" defined above works for all.

build-app-gen:
  stage: build
  rules:
    - if: $CI_PIPELINE_SOURCE == "trigger"
  script:
    - echo "The account used to build the pipeline is `whoami`."
    - echo "Project to build is $PROJ_TO_BUILD  Building ..."
    - echo "Printing some predefined pipeline variables:"
    - echo "CI_PROJECT_URL is   $CI_PROJECT_URL"
    - echo "CI_REPOSITORY_URL is  $CI_REPOSITORY_URL"
    - echo "CI_PROJECT_DIR is  $CI_PROJECT_DIR"
    - echo "CI_PROJECT_ID is  $CI_PROJECT_ID"
    - echo "CI_PROJECT_NAME is  $CI_PROJECT_NAME"
    - python3 -m unity_app_generator init $CI_PROJECT_DIR
    - cd $CI_PROJECT_DIR
    - python3 -m unity_app_generator build_docker
    - python3 -m unity_app_generator build_cwl


test-app-gen:
  stage: test
  rules:
    - if: $CI_PIPELINE_SOURCE == "trigger"
  script:
    - echo "The account used to test the pipeline is `whoami`.  Testing ..."


push-app-gen:
  stage: push
  rules:
    - if: $CI_PIPELINE_SOURCE == "trigger"
  script:
    - echo "The account used to push the build result(s) is `whoami`.  Pushing ..."


deploy-app-gen:
  stage: deploy
  rules:
    - if: $CI_PIPELINE_SOURCE == "trigger"
  script:
    - echo "The account used to deploy the build result(s) is `whoami`.  Deploying ..."
