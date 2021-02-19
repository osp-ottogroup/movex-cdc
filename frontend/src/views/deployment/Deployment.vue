<template>
  <div>
    <div class="columns">
      <div class="column is-2 is-offset-1">
        <b-field label="Generate triggers for schema" >
          <b-select v-model="selectedSchema"
                    placeholder="Select a schema"
                    :loading="isLoading"
                    expanded>
            <option v-for="schema in schemas" :key="schema.id" :value="schema">
              {{ schema.name }}
            </option>
          </b-select>
        </b-field>
        <b-button @click="generateForSelectedSchema"
                  type="is-primary"
                  expanded
                  :disabled="selectedSchema === null || isGeneratingForSchema || isGeneratingForAllSchemas"
                  :loading="isGeneratingForSchema">
          Generate for Schema
        </b-button>
      </div>
      <div class="column is-2 is-offset-1">
        <b-field label="Generate triggers for all schemas" >
          <b-button @click="generateForAllSchemas"
                    type="is-primary"
                    expanded
                    :disabled="isGeneratingForAllSchemas || isGeneratingForSchema"
                    :loading="isGeneratingForAllSchemas">
            Generate for All Schemas
          </b-button>
        </b-field>
      </div>
    </div>
    <div v-if="showResultList" class="columns">
      <div class="column is-10 is-offset-1">
        <h4 class="title is-4">Triggers that are newly generated or modified by this request:</h4>
        <div v-for="(result, index) in resultList" :key="index">
          <h5 class="subtitle is-5">Schema: {{result.schema_name}}</h5>
          <div v-for="(entry, index) in result.successes" :key="index" class="columns result-entry">
            <div class="column is-3">{{entry.trigger_name}}</div>
            <div class="column is-9">
              <pre>{{entry.sql}}</pre>
            </div>
          </div>
        </div>
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

export default {
  name: 'Deployment',
  data() {
    return {
      isLoading: false,
      isGeneratingForSchema: false,
      isGeneratingForAllSchemas: false,
      schemas: [],
      selectedSchema: null,
      resultList: null,
      user: UserService.getUser(),
    };
  },
  async created() {
    await this.loadSchemas();
  },
  computed: {
    showResultList() {
      return this.resultList && this.resultList.length > 0;
    },
  },
  methods: {
    async loadSchemas() {
      try {
        this.isLoading = true;
        this.schemas = await CRUDService.users.deployableSchemas(this.user);
      } catch (e) {
        this.$buefy.notification.open({
          message: getErrorMessageAsHtml(e, 'An error occurred while loading schemas!'),
          type: 'is-danger',
          indefinite: true,
          position: 'is-top',
        });
      } finally {
        this.isLoading = false;
      }
    },
    async generateForSelectedSchema() {
      try {
        this.isGeneratingForSchema = true;
        const response = await HttpService.post(`${Config.backendUrl}/db_triggers/generate`, { schema_name: this.selectedSchema.name });
        if (response.data) {
          this.resultList = response.data.results;
        }
      } catch (e) {
        this.$buefy.notification.open({
          message: getErrorMessageAsHtml(e, 'An error occurred while generating the triggers'),
          type: 'is-danger',
          indefinite: true,
          position: 'is-top',
        });
      } finally {
        this.isGeneratingForSchema = false;
      }
    },
    async generateForAllSchemas() {
      try {
        this.isGeneratingForAllSchemas = true;
        const response = await HttpService.post(`${Config.backendUrl}/db_triggers/generate_all`);
        this.resultList = response.data.results;
      } catch (e) {
        this.$buefy.notification.open({
          message: getErrorMessageAsHtml(e, 'An error occurred while generating the triggers'),
          type: 'is-danger',
          indefinite: true,
          position: 'is-top',
        });
      } finally {
        this.isGeneratingForAllSchemas = false;
      }
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
