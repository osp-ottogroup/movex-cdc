<template>
  <div>
    <table-table :table="tables"></table-table>
    <button class="button" @click="isTableModalActive = true">Add Table</button>
    <table-modal :isActive.sync="isTableModalActive" :tables="dbTables"></table-modal>
  </div>
</template>

<script>
import TableTable from './TableTable.vue';
import TableModal from './TableModal.vue';

export default {
  name: 'TableSelector',
  components: {
    TableTable,
    TableModal,
  },
  props: {
    tables: { type: Array, default: () => [] },
    dbTables: { type: Array, default: () => [] },
  },
  data() {
    return {
      isTableModalActive: false,
    };
  },
};
</script>
