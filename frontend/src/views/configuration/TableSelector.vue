<template>
  <div class="content">
    <h6>Tables</h6>
    <table-table :tables="tables"
                 v-on="$listeners"/>
    <button class="button" @click="isTableModalActive = true">Add Table</button>
    <table-modal :isActive.sync="isTableModalActive" :tables="dbTables"
                 @add-table="onAddTable"></table-modal>
  </div>
</template>

<script>
import TableTable from './TableTable.vue';
import TableModal from './TableModal.vue';
import CRUDService from '@/services/CRUDService';

export default {
  name: 'TableSelector',
  components: {
    TableTable,
    TableModal,
  },
  props: {
    schema: { type: Object, default: () => {} },
  },
  data() {
    return {
      isTableModalActive: false,
      tables: [],
      dbTables: [],
    };
  },
  methods: {
    async onAddTable(addedTable) {
      try {
        const table = await CRUDService.tables.create({
          table: {
            schema_id: this.schema.id,
            name: addedTable.name,
            info: 'TODO',
          },
        });
        this.tables.push(table);
        this.isTableModalActive = false;
        this.$buefy.toast.open({
          message: 'Table added to TriXX configuration!',
          type: 'is-success',
        });
      } catch (e) {
        this.$buefy.toast.open({
          message: 'An error occurred!',
          type: 'is-danger',
          duration: 5000,
        });
      }
    },
  },
  watch: {
    async schema(newSchema) {
      try {
        this.tables = await CRUDService.tables.getAll({ schema_id: newSchema.id });
        this.dbTables = await CRUDService.dbTables.getAll({ schema_name: newSchema.name });
      } catch (e) {
        this.$buefy.toast.open({
          message: 'An error occurred while loading tables!',
          type: 'is-danger',
          duration: 5000,
        });
      }
    },
  },
};
</script>
