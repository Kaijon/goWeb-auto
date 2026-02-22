// Declarative Jenkins Pipeline — Embedded Camera UI Self-Healing CI/CD
// Triggered by GitLab webhook on issue events.
// Reads issue → generates code via Copilot API → builds → tests → self-heals → reports.

pipeline {
    agent any

    // ---------------------------------------------------------------------------
    // Parameters (can be overridden per-build or injected by webhook payload)
    // ---------------------------------------------------------------------------
    parameters {
        string(
            name: 'GITLAB_PROJECT_ID',
            defaultValue: '',
            description: 'GitLab project ID (numeric). Injected by webhook.'
        )
        string(
            name: 'ISSUE_IID',
            defaultValue: '',
            description: 'GitLab issue internal ID. Injected by webhook.'
        )
        string(
            name: 'ISSUE_BODY',
            defaultValue: '',
            description: 'Raw issue description text. Injected by webhook.'
        )
        string(
            name: 'ISSUE_TITLE',
            defaultValue: '',
            description: 'Issue title for context. Injected by webhook.'
        )
        choice(
            name: 'GENERATE_TARGET',
            choices: ['web-ui', 'tests', 'both'],
            description: 'Which asset to (re)generate. Parsed from issue labels if empty.'
        )
        string(
            name: 'MAX_HEAL_ATTEMPTS',
            defaultValue: '3',
            description: 'Maximum self-heal retry loops before marking build UNSTABLE.'
        )
        booleanParam(
            name: 'CLOSE_ISSUE_ON_SUCCESS',
            defaultValue: true,
            description: 'Automatically close the GitLab issue when all tests pass.'
        )
    }

    // ---------------------------------------------------------------------------
    // Environment — secrets injected from Jenkins Credentials store
    // ---------------------------------------------------------------------------
    environment {
        GITLAB_TOKEN      = credentials('GITLAB_TOKEN')
        GITLAB_API_URL    = credentials('GITLAB_API_URL')
        GITHUB_TOKEN      = credentials('GITHUB_TOKEN')
        COPILOT_API_URL   = credentials('COPILOT_API_URL')    // e.g. https://models.inference.ai.azure.com
        COPILOT_MODEL     = 'gpt-4o'

        // Workspace-relative paths
        SCRIPTS_DIR       = 'scripts'
        DIST_DIR          = 'dist'
        TEST_RESULTS_JSON = 'test-results.json'
        TEST_REPORT_HTML  = 'test-report.html'
        HEAL_CONTEXT_FILE = '.heal-context.json'

        // Simulator config
        SIMULATOR_PORT    = '8080'
        SIMULATOR_PID     = '.simulator.pid'
    }

    options {
        timeout(time: 30, unit: 'MINUTES')
        disableConcurrentBuilds()
        buildDiscarder(logRotator(numToKeepStr: '20'))
        ansiColor('xterm')
    }

    // ---------------------------------------------------------------------------
    // Stages
    // ---------------------------------------------------------------------------
    stages {

        // -----------------------------------------------------------------------
        // 1. Parse the GitLab issue to extract requirements
        // -----------------------------------------------------------------------
        stage('Read GitLab Issue') {
            steps {
                echo "=== Stage 1: Reading GitLab Issue #${params.ISSUE_IID} ==="
                sh """
                    chmod +x ${SCRIPTS_DIR}/*.sh
                    ${SCRIPTS_DIR}/read-gitlab-issue.sh \
                        "${GITLAB_API_URL}" \
                        "${GITLAB_TOKEN}" \
                        "${params.GITLAB_PROJECT_ID}" \
                        "${params.ISSUE_IID}" \
                        > issue-context.json
                """
                script {
                    def issueCtx = readJSON file: 'issue-context.json'
                    env.ISSUE_TITLE_RESOLVED = issueCtx.title ?: params.ISSUE_TITLE
                    env.ISSUE_BODY_RESOLVED  = issueCtx.body  ?: params.ISSUE_BODY
                    env.ISSUE_LABELS         = issueCtx.labels?.join(',') ?: ''
                    echo "Issue: ${env.ISSUE_TITLE_RESOLVED}"
                    echo "Labels: ${env.ISSUE_LABELS}"
                }
            }
        }

        // -----------------------------------------------------------------------
        // 2. Generate / update Vue.js web UI component via Copilot API
        // -----------------------------------------------------------------------
        stage('Generate Web UI') {
            when {
                expression {
                    params.GENERATE_TARGET == 'web-ui' || params.GENERATE_TARGET == 'both'
                }
            }
            steps {
                echo "=== Stage 2: Generating Web UI via Copilot ==="
                sh """
                    ${SCRIPTS_DIR}/copilot-generate.sh \
                        --prompt     ".github/prompts/generate-camera-ui.prompt.md" \
                        --system     ".github/copilot-instructions.md" \
                        --spec       "docs/specs/bitrate-policy.md" \
                        --context    "issue-context.json" \
                        --out-file   "src/components/CameraConfig.vue" \
                        --heal-file  "${HEAL_CONTEXT_FILE}" \
                        --api-url    "${COPILOT_API_URL}" \
                        --model      "${COPILOT_MODEL}"
                """
            }
        }

        // -----------------------------------------------------------------------
        // 3. Build the Vue.js frontend
        // -----------------------------------------------------------------------
        stage('Build Frontend') {
            steps {
                echo "=== Stage 3: Building Frontend ==="
                sh """
                    npm ci --prefer-offline
                    npm run build
                """
            }
            post {
                failure {
                    script {
                        // Inject build error into heal context for next iteration
                        sh """
                            echo '{"stage":"build","error":"npm run build failed. See Jenkins console."}' \
                                > ${HEAL_CONTEXT_FILE}
                        """
                    }
                }
            }
        }

        // -----------------------------------------------------------------------
        // 4. Generate / update Go test files via Copilot API
        // -----------------------------------------------------------------------
        stage('Generate Tests') {
            when {
                expression {
                    params.GENERATE_TARGET == 'tests' || params.GENERATE_TARGET == 'both'
                }
            }
            steps {
                echo "=== Stage 4: Generating Test Suite via Copilot ==="
                sh """
                    ${SCRIPTS_DIR}/copilot-generate.sh \
                        --prompt     ".github/prompts/generate-host-tests.prompt.md" \
                        --system     ".github/copilot-instructions.md" \
                        --spec       "docs/specs/bitrate-policy.md" \
                        --context    "issue-context.json" \
                        --out-file   "cmd/server/main_test.go" \
                        --secondary  "tests/integration_test.go" \
                        --heal-file  "${HEAL_CONTEXT_FILE}" \
                        --api-url    "${COPILOT_API_URL}" \
                        --model      "${COPILOT_MODEL}"
                """
            }
        }

        // -----------------------------------------------------------------------
        // 5. Launch the Go host simulator
        // -----------------------------------------------------------------------
        stage('Start Simulator') {
            steps {
                echo "=== Stage 5: Starting Go Host Simulator on :${SIMULATOR_PORT} ==="
                sh """
                    ${SCRIPTS_DIR}/run-simulation.sh start \
                        "${SIMULATOR_PORT}" \
                        "${DIST_DIR}" \
                        "${SIMULATOR_PID}"
                """
                // Brief wait for the server to be ready
                sh "sleep 2"
                sh "curl -sf http://localhost:${SIMULATOR_PORT}/ -o /dev/null || (echo 'Simulator did not start' && exit 1)"
            }
        }

        // -----------------------------------------------------------------------
        // 6. Run the Go test suite with JSON output and coverage
        // -----------------------------------------------------------------------
        stage('Run Tests') {
            steps {
                echo "=== Stage 6: Running Test Suite ==="
                sh """
                    ${SCRIPTS_DIR}/run-simulation.sh test \
                        "${TEST_RESULTS_JSON}"
                """
            }
            post {
                always {
                    // Stop simulator regardless of test outcome
                    sh "${SCRIPTS_DIR}/run-simulation.sh stop '${SIMULATOR_PID}'"
                }
                failure {
                    script {
                        // Extract failure context into heal file for self-heal loop
                        sh """
                            ${SCRIPTS_DIR}/self-heal.sh extract \
                                "${TEST_RESULTS_JSON}" \
                                "${HEAL_CONTEXT_FILE}"
                        """
                    }
                }
            }
        }

        // -----------------------------------------------------------------------
        // 7. Self-Heal loop — re-generate and re-test on failure
        //    Groovy loop runs entirely in-agent (no additional stage nesting required)
        // -----------------------------------------------------------------------
        stage('Self-Heal') {
            when {
                expression {
                    // Only enter if tests produced failure data
                    return fileExists(HEAL_CONTEXT_FILE) && sh(
                        script: "jq -e '.failures | length > 0' ${HEAL_CONTEXT_FILE}",
                        returnStatus: true
                    ) == 0
                }
            }
            steps {
                echo "=== Stage 7: Self-Heal Engine ==="
                script {
                    int maxAttempts = params.MAX_HEAL_ATTEMPTS.toInteger()
                    boolean healed   = false

                    for (int attempt = 1; attempt <= maxAttempts; attempt++) {
                        echo "--- Self-Heal Attempt ${attempt}/${maxAttempts} ---"

                        // Re-generate code with failure context appended to prompt
                        sh """
                            ${SCRIPTS_DIR}/copilot-generate.sh \
                                --prompt     ".github/prompts/generate-camera-ui.prompt.md" \
                                --system     ".github/copilot-instructions.md" \
                                --spec       "docs/specs/bitrate-policy.md" \
                                --context    "issue-context.json" \
                                --out-file   "src/components/CameraConfig.vue" \
                                --heal-file  "${HEAL_CONTEXT_FILE}" \
                                --api-url    "${COPILOT_API_URL}" \
                                --model      "${COPILOT_MODEL}" \
                                --heal-mode
                        """
                        // Also re-generate server if Go tests failed
                        sh """
                            ${SCRIPTS_DIR}/copilot-generate.sh \
                                --prompt     ".github/prompts/generate-host-tests.prompt.md" \
                                --system     ".github/copilot-instructions.md" \
                                --spec       "docs/specs/bitrate-policy.md" \
                                --context    "issue-context.json" \
                                --out-file   "cmd/server/main_test.go" \
                                --heal-file  "${HEAL_CONTEXT_FILE}" \
                                --api-url    "${COPILOT_API_URL}" \
                                --model      "${COPILOT_MODEL}" \
                                --heal-mode
                        """

                        // Rebuild and retest
                        int buildStatus = sh(
                            script: "npm run build 2>&1",
                            returnStatus: true
                        )
                        if (buildStatus != 0) {
                            echo "Build failed on attempt ${attempt}, continuing..."
                            continue
                        }

                        sh "${SCRIPTS_DIR}/run-simulation.sh start '${SIMULATOR_PORT}' '${DIST_DIR}' '${SIMULATOR_PID}'"
                        sh "sleep 2"

                        int testStatus = sh(
                            script: "${SCRIPTS_DIR}/run-simulation.sh test '${TEST_RESULTS_JSON}'",
                            returnStatus: true
                        )
                        sh "${SCRIPTS_DIR}/run-simulation.sh stop '${SIMULATOR_PID}'"

                        if (testStatus == 0) {
                            echo "Self-heal succeeded on attempt ${attempt}"
                            sh "rm -f ${HEAL_CONTEXT_FILE}"
                            healed = true
                            break
                        }

                        // Update heal context with new failures for next round
                        sh """
                            ${SCRIPTS_DIR}/self-heal.sh extract \
                                "${TEST_RESULTS_JSON}" \
                                "${HEAL_CONTEXT_FILE}"
                        """
                    }

                    if (!healed) {
                        echo "Self-heal exhausted after ${maxAttempts} attempts. Marking UNSTABLE."
                        currentBuild.result = 'UNSTABLE'
                    }
                }
            }
        }

        // -----------------------------------------------------------------------
        // 8. Generate the interactive HTML test report
        // -----------------------------------------------------------------------
        stage('Generate Report') {
            steps {
                echo "=== Stage 8: Generating HTML Test Report ==="
                sh """
                    ${SCRIPTS_DIR}/generate-report.sh \
                        --results   "${TEST_RESULTS_JSON}" \
                        --prompt    ".github/prompts/generate-test-report.prompt.md" \
                        --api-url   "${COPILOT_API_URL}" \
                        --model     "${COPILOT_MODEL}" \
                        --out-file  "${TEST_REPORT_HTML}" \
                        --build-url "${BUILD_URL}"
                """
            }
            post {
                always {
                    // Archive report as Jenkins artifact
                    archiveArtifacts artifacts: "${TEST_REPORT_HTML}", fingerprint: true
                    // Publish HTML report in Jenkins sidebar
                    publishHTML(target: [
                        reportName:  'Test Report',
                        reportDir:   '.',
                        reportFiles: "${TEST_REPORT_HTML}",
                        keepAll:     true,
                        alwaysLinkToLastBuild: true
                    ])
                }
            }
        }

        // -----------------------------------------------------------------------
        // 9. Post results back to the GitLab issue
        // -----------------------------------------------------------------------
        stage('Notify GitLab') {
            steps {
                echo "=== Stage 9: Posting Results to GitLab Issue #${params.ISSUE_IID} ==="
                sh """
                    ${SCRIPTS_DIR}/notify-gitlab.sh \
                        --api-url    "${GITLAB_API_URL}" \
                        --token      "${GITLAB_TOKEN}" \
                        --project-id "${params.GITLAB_PROJECT_ID}" \
                        --issue-iid  "${params.ISSUE_IID}" \
                        --results    "${TEST_RESULTS_JSON}" \
                        --report-url "${BUILD_URL}artifact/${TEST_REPORT_HTML}" \
                        --build-url  "${BUILD_URL}" \
                        --close      "${params.CLOSE_ISSUE_ON_SUCCESS}" \
                        --healed     "${fileExists(HEAL_CONTEXT_FILE) ? 'false' : 'true'}"
                """
            }
        }
    }

    // ---------------------------------------------------------------------------
    // Post-pipeline actions
    // ---------------------------------------------------------------------------
    post {
        always {
            // Clean up simulator if still running
            sh "[ -f ${SIMULATOR_PID} ] && kill \$(cat ${SIMULATOR_PID}) 2>/dev/null || true"
            // Archive raw test JSON for audit
            archiveArtifacts artifacts: "${TEST_RESULTS_JSON}", allowEmptyArchive: true
        }
        success {
            echo "Pipeline completed successfully. Issue #${params.ISSUE_IID} closed."
        }
        unstable {
            echo "Pipeline completed UNSTABLE — self-heal could not fix all failures."
        }
        failure {
            // On hard failure (infra/config issues), notify GitLab with error label
            sh """
                ${SCRIPTS_DIR}/notify-gitlab.sh \
                    --api-url    "${GITLAB_API_URL}" \
                    --token      "${GITLAB_TOKEN}" \
                    --project-id "${params.GITLAB_PROJECT_ID}" \
                    --issue-iid  "${params.ISSUE_IID}" \
                    --error      "Pipeline infrastructure failure. See: ${BUILD_URL}" \
                    --label      "pipeline-failed" || true
            """
        }
        cleanup {
            sh "rm -f issue-context.json ${HEAL_CONTEXT_FILE} ${SIMULATOR_PID} || true"
        }
    }
}
