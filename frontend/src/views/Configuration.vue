<template>
  <div class="columns is-centered">
    <schema-selector class="column is-2 is-offset-2"
                     :schemas="schemas"
                     @schema-selected="onSchemaSelected"></schema-selector>
    <table-selector class="column is-2"
                    :tables="tables"
                    :dbTables="dbTables"></table-selector>
    <column-selector class="column is-6"></column-selector>
  </div>
</template>

<script>
import SchemaSelector from '../components/SchemaSelector.vue';
import TableSelector from '../components/TableSelector.vue';
import ColumnSelector from '../components/ColumnSelector.vue';
import CRUDService from '../services/CRUDServices';
import HttpService from '../services/HttpService';
import Config from '../config/config';

export default {
  name: 'configuration',
  components: {
    SchemaSelector,
    TableSelector,
    ColumnSelector,
  },
  data() {
    return {
      schemas: [],
      tables: [],
      dbTables: [],
    };
  },
  async mounted() {
    this.schemas = await CRUDService.schemas.getAll();
  },
  methods: {
    async onSchemaSelected(schema) {
      this.tables = (await HttpService.get(`${Config.backendUrl}/tables`, { schema_id: schema.id })).data;
      this.dbTables = (await HttpService.get(`${Config.backendUrl}/db_tables`, { schema_name: schema.name })).data;
    },
  },
};
</script>
