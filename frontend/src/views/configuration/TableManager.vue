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
      Add table to observe
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
      // initialize array with one empty object; will be reseted in 'mounted' hook
      // this is because buefy-table would otherwise not render headers
      tables: [{}],
      dbTables: [],
      modal: {
        table: null,
        mode: null,
      },
    };
  },
  mounted() {
    this.tables = [];
  },
  computed: {
    selectableTables() {
      // filter all tables out of db tables, that are not included in trixx tables
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
        this.$buefy.notification.open({
          message: getErrorMessageAsHtml(e, 'An error occurred while loading tables!'),
          type: 'is-danger',
          indefinite: true,
          position: 'is-top',
        });
      }
    },
    onAddTable() {
      this.modal.mode = 'ADD';
      this.modal.table = {
        id: null,
        schema_id: this.schema.id,
        name: '',
        info: '',
        topic: '',
        kafka_key_handling: 'N',
        fixed_message_key: '',
      };
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
        this.$buefy.notification.open({
          message: getErrorMessageAsHtml(e),
          type: 'is-danger',
          indefinite: true,
          position: 'is-top',
        });
      }
    },
    async createTable(table) {
      try {
        const createdTable = await CRUDService.tables.create({ table });
        this.tables.push(createdTable);
        this.tables = this.tables.sort((a, b) => {
          const aName = a.name.toUpperCase();
          const bName = b.name.toUpperCase();
          if (aName < bName) { return -1; }
          if (aName > bName) { return 1; }
          return 0;
        });
        this.$buefy.toast.open({
          message: `Table '${createdTable.name}' added to TriXX configuration!`,
          type: 'is-success',
        });
      } catch (e) {
        this.$buefy.notification.open({
          message: getErrorMessageAsHtml(e),
          type: 'is-danger',
          indefinite: true,
          position: 'is-top',
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
          tables.kafka_key_handling = updatedTable.kafka_key_handling;
          tables.fixed_message_key = updatedTable.fixed_message_key;
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
