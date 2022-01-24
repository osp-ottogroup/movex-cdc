<template>
  <div class="container">
    <div class="columns">
       <div class="column is-3">
        <div class="is-size-7 has-text-info-dark mb-3">
          <b-icon icon="information-outline" size="is-small" />
          <span>
            You can only generate triggers for schemas, for which you have deployment rights.
            This also includes the option "All Schemas".
          </span>
        </div>
        <b-field>
          <b-select v-model="selectedSchema"
                    placeholder="Select a schema"
                    expanded
                    :loading="isLoading">
            <option value="ALL_SCHEMAS">- All Schemas -</option>
            <option v-for="schema in schemas" :key="schema.id" :value="schema">
              {{ schema.name }}
            </option>
          </b-select>
        </b-field>
        <b-button @click="onGenerateClicked"
                  type="is-primary"
                  expanded
                  :disabled="selectedSchema === null || isGenerating || isDeploying"
                  :loading="isGenerating">
          Generate for Schema
        </b-button>
      </div>
    </div>

    <div v-if="dryRunResultList.length > 0 && deployResultList.length === 0">
      <div>
        <h4 class="title is-5">Triggers that would be newly generated or modified</h4>
        <DeploymentResults :deployment-results="dryRunResultList"
                           :enable-switches="true"
        />
      </div>
      <div class="columns is-mobile mt-1">
        <div class="column is-one-quarter">
          <b-button @click="onDeployClicked"
                    type="is-primary"
                    expanded
                    :disabled="!isDeployable || isGenerating || isDeploying"
                    :loading="isGenerating">
            Deploy
          </b-button>
        </div>
      </div>
    </div>

    <div v-if="deployResultList.length > 0" class="mt-5">
      <div>
        <h4 class="title is-5">Triggers that are newly generated or modified</h4>
        <DeploymentResults :deployment-results="deployResultList" :enable-switches="false"/>
      </div>
    </div>

  </div>
</template>

<script>
import CRUDService from '@/services/CRUDService';
import { getErrorMessageAsHtml } from '@/helpers';
import HttpService from '@/services/HttpService';
import Config from '@/config/config';
import UserService from '@/services/UserService';
import DeploymentResults from '@/views/deployment/DeploymentResults.vue';

export default {
  // TODO change to multi word component name
  // eslint-disable-next-line vue/multi-word-component-names
  name: 'Deployment',
  components: {
    DeploymentResults,
  },
  data() {
    return {
      isLoading: false,
      isGenerating: false,
      isDeploying: false,
      schemas: [],
      selectedSchema: null,
      dryRunResultList: [],
      deployResultList: [],
      user: UserService.getUser(),
    };
  },
  async created() {
    await this.loadSchemas();
  },
  computed: {
    isDeployable() {
      return this.dryRunResultList.some((schema) => schema.tables.some((table) => table.deploy));
    },
  },
  methods: {
    showErrorNotification(e, message) {
      this.$buefy.notification.open({
        message: getErrorMessageAsHtml(e, message),
        type: 'is-danger',
        indefinite: true,
        position: 'is-top',
      });
    },
    async loadSchemas() {
      try {
        this.isLoading = true;
        this.schemas = await CRUDService.users.deployableSchemas(this.user);
      } catch (e) {
        this.showErrorNotification(e, 'An error occurred while loading schemas!');
      } finally {
        this.isLoading = false;
      }
    },
    async onGenerateClicked() {
      try {
        this.dryRunResultList = [];
        this.deployResultList = [];
        this.isGenerating = true;
        const data = { dry_run: true };
        let response = null;
        if (this.selectedSchema === 'ALL_SCHEMAS') {
          response = await HttpService.post(`${Config.backendUrl}/db_triggers/generate_all`, data);
        } else {
          data.schema_name = this.selectedSchema.name;
          response = await HttpService.post(`${Config.backendUrl}/db_triggers/generate`, data);
        }
        if (response.data) {
          this.dryRunResultList = this.prepareResults(response.data.results);
        }
      } catch (e) {
        this.showErrorNotification(e, 'An error occurred while generating the triggers');
      } finally {
        this.isGenerating = false;
      }
    },
    async onDeployClicked() {
      try {
        this.isGenerating = true;
        const tableIdList = [];
        this.dryRunResultList.forEach((schema) => {
          schema.tables.forEach((table) => {
            if (table.deploy) {
              tableIdList.push(table.tableId);
            }
          });
        });
        const data = {
          dry_run: false,
          table_id_list: tableIdList,
        };
        let response = null;
        if (this.selectedSchema === 'ALL_SCHEMAS') {
          response = await HttpService.post(`${Config.backendUrl}/db_triggers/generate_all`, data);
        } else {
          data.schema_name = this.selectedSchema.name;
          response = await HttpService.post(`${Config.backendUrl}/db_triggers/generate`, data);
        }
        if (response.data) {
          this.deployResultList = this.prepareResults(response.data.results);
        }
      } catch (e) {
        this.showErrorNotification(e, 'An error occurred while deploying the triggers');
      } finally {
        this.isGenerating = false;
      }
    },
    prepareResults(rawResults) {
      const results = [];
      rawResults.forEach((result) => {
        const tableMap = new Map();

        const initMap = (entry) => {
          if (!tableMap.has(entry.table_name)) {
            tableMap.set(entry.table_name, {
              tableId: entry.table_id,
              tableName: entry.table_name,
              successfulTriggers: [],
              erroneousTriggers: [],
              loadSql: '',
              deploy: false,
            });
          }
        };

        result.successes.forEach(initMap);
        result.errors.forEach(initMap);
        result.load_sqls.forEach(initMap);

        result.successes.forEach((entry) => {
          tableMap.get(entry.table_name).successfulTriggers.push({
            triggerName: entry.trigger_name,
            triggerSql: entry.sql,
          });
        });

        result.errors.forEach((entry) => {
          tableMap.get(entry.table_name).erroneousTriggers.push({
            triggerName: entry.trigger_name,
            triggerSql: entry.sql,
            exceptionClass: entry.exception_class,
            exceptionMessage: entry.exception_message,
          });
        });

        result.load_sqls.forEach((entry) => {
          tableMap.get(entry.table_name).loadSql = entry.sql;
        });
        const schemaData = {
          schemaName: result.schema_name,
          tables: [...tableMap.values()],
          errorCount: result.errors.length,
        };

        results.push(schemaData);
      });

      return results;
    },
  },
};
</script>

<style lang="scss" scoped>
  .subtitle {
    background-color: lightgray;
  }
  .result-entry:not(:last-child) {
    border-bottom: 1px solid lightgray;
  }
</style>
