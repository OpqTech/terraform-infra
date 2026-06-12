pipeline {
  agent { label 'terraform' }

  options {
    //disableConcurrentBuilds()
    timestamps()
    timeout(time: 1, unit: 'HOURS')
  }

  parameters {
    choice(name: 'INFRA', description: 'Terraform module to operate on', choices: "iam\nvpc\nrds\neks")
    choice(name: 'ENV', description: 'Target environment / Terraform workspace', choices: "dev\nqa\nuat\nprod")
    choice(name: 'AWS_REGION', description: 'AWS region', choices: "ap-south-1")
  }

  environment {
    AWS_DEFAULT_REGION = "${params.AWS_REGION}"
    PATH               = "${HOME}/.local/bin:${WORKSPACE}/.bin:${env.PATH}"
    TFLINT_VERSION     = "v0.55.0"
    TRIVY_VERSION      = "v0.71.0"
    CHECKOV_VERSION    = "3.3.1"
  }

  stages {
    stage('Prerequisites') {
      steps {
        sh '''
          set -euo pipefail

          sudo dpkg --configure -a
          sudo apt-get update -y
          sudo apt-get install -y curl jq unzip gettext-base python3 python3-pip

          if ! command -v aws > /dev/null; then
            echo "Installing AWS CLI..."
            curl -fsS "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o awscliv2.zip
            unzip -q awscliv2.zip
            sudo ./aws/install
            rm -rf awscliv2.zip aws
          fi

          mkdir -p "${WORKSPACE}/.bin"

          if [ ! -x "${WORKSPACE}/.bin/kubectl" ]; then
            echo "Installing kubectl..."
            KUBECTL_VERSION=$(curl -fsSL https://dl.k8s.io/release/stable.txt)
            curl -fsSL "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl" -o "${WORKSPACE}/.bin/kubectl"
            chmod +x "${WORKSPACE}/.bin/kubectl"
          fi

          if [ ! -x "${WORKSPACE}/.bin/tflint" ]; then
            echo "Installing tflint ${TFLINT_VERSION}..."
            curl -fsSL "https://github.com/terraform-linters/tflint/releases/download/${TFLINT_VERSION}/tflint_linux_amd64.zip" -o tflint.zip
            unzip -q -o tflint.zip -d "${WORKSPACE}/.bin"
            rm -f tflint.zip
          fi

          if [ ! -x "${WORKSPACE}/.bin/trivy" ]; then
            echo "Installing trivy ${TRIVY_VERSION}..."
            curl -fsSL "https://github.com/aquasecurity/trivy/releases/download/${TRIVY_VERSION}/trivy_${TRIVY_VERSION#v}_Linux-64bit.tar.gz" -o trivy.tar.gz
            tar -xzf trivy.tar.gz -C "${WORKSPACE}/.bin" trivy
            rm -f trivy.tar.gz
          fi

          if ! command -v checkov > /dev/null; then
            echo "Installing Checkov ${CHECKOV_VERSION}..."
            python3 -m pip install --user --break-system-packages "checkov==${CHECKOV_VERSION}"
          fi

          aws --version
          tflint --version
          trivy --version
          PATH="${HOME}/.local/bin:${PATH}" checkov --version
        '''
      }
    }

    stage('Format') {
      steps {
        dir("${params.INFRA}") {
          sh 'terraform fmt -check -recursive -diff'
        }
      }
    }

    stage('Lint') {
      steps {
        dir("${params.INFRA}") {
          sh '''
            set -euo pipefail
            tflint --init
            tflint --recursive --minimum-failure-severity=error
          '''
        }
      }
    }

    stage('Trivy Sec Check') {
      steps {
        dir("${params.INFRA}") {
          sh 'trivy config --exit-code 1 .'
        }
      }
    }

    stage('Checkov Security Check') {
      steps {
        dir("${params.INFRA}") {
          sh '''
            set -euo pipefail
            PATH="${HOME}/.local/bin:${PATH}"
            checkov -d . --framework terraform --compact
          '''
        }
      }
    }

    stage('Init') {
      steps {
        dir("${params.INFRA}") {
          withCredentials([[$class: 'AmazonWebServicesCredentialsBinding', credentialsId: 'awsCred']]) {
            sh '''
              set -euo pipefail
              terraform init -input=false
              terraform workspace select "$ENV" || terraform workspace new "$ENV"
            '''
          }
        }
      }
    }

    stage('Validate') {
      steps {
        dir("${params.INFRA}") {
          sh 'terraform validate'
        }
      }
    }

    stage('Plan') {
      steps {
        dir("${params.INFRA}") {
          withCredentials([[$class: 'AmazonWebServicesCredentialsBinding', credentialsId: 'awsCred']]) {
            sh """
              terraform plan -no-color -out='${params.INFRA}.tfplan' -parallelism=50 -var-file="environments/${params.ENV}.auto.tfvars.json"
            """
          }
        }
      }
    }

    stage('Approve deploy') {
      steps {
        input message: "Apply the ${params.INFRA} plan for ${params.ENV}?"
      }
    }

    stage('Apply') {
      steps {
        dir("${params.INFRA}") {
          withCredentials([[$class: 'AmazonWebServicesCredentialsBinding', credentialsId: 'awsCred']]) {
            sh """
              time terraform apply -no-color -parallelism=50 -input=false '${params.INFRA}.tfplan'
            """

            script {
              if (params.INFRA == 'eks') {
                sh """
                  ./scripts/apply-karpenter-manifests.sh "environments/${params.ENV}.auto.tfvars.json"
                """
              }
            }
          }
        }
      }
    }
  }

  post {
    always {
      dir("${params.INFRA}") {
        sh 'rm -f *.tfplan'
      }
      cleanWs(
        deleteDirs: true,
        disableDeferredWipeout: true,
        notFailBuild: true
      )
    }
  }
}
