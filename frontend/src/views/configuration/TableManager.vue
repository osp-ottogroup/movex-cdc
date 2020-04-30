<template>
  <div>
    <table-table :tables="tables"
                 :schema="schema"
                 v-on="$listeners"
                 @edit-table="onEditTable"/>
    <b-button id="add-table-button"
              v-if="schema"
              class="is-pulled-right"
              @click="onAddTable"
              expanded>
      Add a table to observe
    </b-button>
    <template v-if="showTableModal">
      <table-modal :tables="selectableTables"
                   :table="modal.table"
                   :schema="schema"
                   :mode="modal.mode"
                   @save="onSave"
                   @close="onClose"/>
    </template>
  </div>
</template>

<script>
import TableTable from './TableTable.vue';
import TableModal from './TableModal.vue';
import CRUDService from '@/services/CRUDService';
import { getErrorMessageAsHtml } from '@/helpers';

export default {
  name: 'TableManager',
  components: {
    TableTable,
    TableModal,
  },
  props: {
    schema: { type: Object, default: () => {} },
  },
  data() {
    return {
      tables: [],
      dbTables: [],
      modal: {
        table: null,
        mode: null,
      },
    };
  },
  computed: {
    selectableTables() {
      // filter all tables out of db tables, that are not included in trixx tables
      // eslint-disable-next-line max-len
      return this.dbTables.filter(dbTable => !this.tables.some(table => dbTable.name === table.name));
    },
    showTableModal() {
      return this.modal.table !== null;
    },
  },
  methods: {
    async loadTables(schema) {
      try {
        this.tables = await CRUDService.tables.getAll({ schema_id: schema.id });
        this.dbTables = await CRUDService.dbTables.getAll({ schema_name: schema.name });
      } catch (e) {
        this.$buefy.toast.open({
          message: getErrorMessageAsHtml(e, 'An error occurred while loading tables!'),
          type: 'is-danger',
          duration: 5000,
        });
      }
    },
    onAddTable() {
      this.modal.mode = 'ADD';
      this.modal.table = {};
    },
    onEditTable(table) {
      this.modal.mode = 'EDIT';
      this.modal.table = { ...table };
    },
    onClose() {
      this.modal.table = null;
    },
    async onSave(table) {
      try {
        if (table.id) {
          await this.updateTable(table);
        } else {
          await this.createTable(table);
        }
        this.modal.table = null;
        this.modal.mode = null;
      } catch (e) {
        this.$buefy.toast.open({
          message: getErrorMessageAsHtml(e),
          type: 'is-danger',
          duration: 5000,
        });
      }
    },
    async createTable(table) {
      try {
        const createdTable = await CRUDService.tables.create({
          table: {
            schema_id: this.schema.id,
            name: table.name,
            topic: table.topic,
            info: table.info,
          },
        });
        this.tables.push(createdTable);
        this.$buefy.toast.open({
          message: `Table '${createdTable.name}' added to TriXX configuration!`,
          type: 'is-success',
        });
      } catch (e) {
        this.$buefy.toast.open({
          message: getErrorMessageAsHtml(e),
          type: 'is-danger',
          duration: 5000,
        });
      }
    },
    async updateTable(table) {
      const updatedTable = await CRUDService.tables.update(table.id, { table });
      this.$buefy.toast.open({
        message: `Saved changes to table '${table.name}'!`,
        type: 'is-success',
      });
      // TODO needs a better way of copying properties without dereferencing original object
      this.tables.some((tables) => {
        if (tables.id === updatedTable.id) { /* eslint-disable no-param-reassign */
          tables.name = updatedTable.name;
          tables.topic = updatedTable.topic;
          tables.info = updatedTable.info;
          tables.created_at = updatedTable.created_at;
          tables.updated_at = updatedTable.updated_at;
          return true;
        }
        return false;
      });
    },
  },
  watch: {
    async schema(newSchema) {
      await this.loadTables(newSchema);
    },
  },
};
</script>

<style lang="scss">
  #add-table-button {
    margin-top: 1em;
  }
</style>
