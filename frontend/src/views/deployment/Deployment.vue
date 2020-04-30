<template>
  <div>
    <div class="columns">
      <div class="column is-2 is-offset-1">
        <b-field label="Generate triggers for schema" >
          <b-select v-model="selectedSchema"
                    placeholder="Select a schema"
                    expanded>
            <option v-for="schema in schemas" :key="schema.id" :value="schema">
              {{ schema.name }}
            </option>
          </b-select>
        </b-field>
        <b-button @click="generateForSelectedSchema" type="is-primary" expanded :disabled="selectedSchema === null">
          Generate for Schema
        </b-button>
      </div>
      <div class="column is-2 is-offset-1">
        <b-field label="Generate triggers for all schemas" >
          <b-button @click="generateForAllSchemas" type="is-primary" expanded>
            Generate for All Schemas
          </b-button>
        </b-field>
      </div>
    </div>
    <div v-if="showResultList" class="columns">
      <div class="column is-10 is-offset-1">
        <h4 class="title is-4">Results</h4>
        <div v-for="(result, index) in resultList" :key="index">
          <h5 class="subtitle is-5">Schema: {{result.schema_name}}</h5>
          <div v-for="(entry, index) in result.successes" :key="index" class="columns result-entry">
            <div class="column is-3">{{entry.trigger_name}}</div>
            <div class="column is-8">{{entry.sql}}</div>
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

export default {
  name: 'Deployment',
  components: {},
  data() {
    return {
      schemas: [],
      selectedSchema: null,
      resultList: null,
    };
  },
  async mounted() {
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
        this.schemas = await CRUDService.schemas.getAll();
      } catch (e) {
        this.$buefy.toast.open({
          message: getErrorMessageAsHtml(e, 'An error occurred while loading schemas!'),
          type: 'is-danger',
          duration: 5000,
        });
      }
    },
    async generateForSelectedSchema() {
      try {
        const response = await HttpService.post(`${Config.backendUrl}/db_triggers/generate`, { schema_name: this.selectedSchema.name });
        if (response.data) {
          // response is single object
          response.data.schema_name = this.selectedSchema.name;
          this.resultList = [response.data];
        }
      } catch (e) {
        this.$buefy.toast.open({
          message: getErrorMessageAsHtml(e, 'An error occurred while generating the triggers'),
          type: 'is-danger',
          duration: 5000,
        });
      }
    },
    async generateForAllSchemas() {
      try {
        const response = await HttpService.post(`${Config.backendUrl}/db_triggers/generate_all`);
        // response is already an array
        this.resultList = response.data;
      } catch (e) {
        this.$buefy.toast.open({
          message: getErrorMessageAsHtml(e, 'An error occurred while generating the triggers'),
          type: 'is-danger',
          duration: 5000,
        });
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
