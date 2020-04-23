<template>
  <div>
    <schema-table :schemas="schemas"
                  v-on="$listeners"
                  @schema-changed="onSchemaChanged"/>
  </div>
</template>

<script>
import SchemaTable from './SchemaTable.vue';
import CRUDService from '../../services/CRUDService';
import { getErrorMessageAsHtml } from '@/helpers';

export default {
  name: 'SchemaSelector',
  components: {
    SchemaTable,
  },
  data() {
    return {
      schemas: [],
    };
  },
  async mounted() {
    await this.loadSchemas();
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
    async onSchemaChanged(done) {
      await this.loadSchemas();
      done();
    },
  },
};
</script>
