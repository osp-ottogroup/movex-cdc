<template>
  <table class="table is-striped is-hoverable">
    <thead>
    <tr>
      <th>
        Tables
      </th>
    </tr>
    </thead>
    <tbody>
    <tr v-for="table in tables"
        :key="table.name"
        @click="setCurrentTable(table)"
        :class="{ 'is-selected': isCurrentTable(table) }">
      <td>{{ table.name }}</td>
    </tr>
    </tbody>
  </table>
</template>

<script>
export default {
  name: 'TableTable',
  props: {
    tables: { type: Array, default: () => [] },
  },
  data() {
    return {
      currentTable: null,
    };
  },
  methods: {
    setCurrentTable(table) {
      this.currentTable = table;
      this.$emit('table-selected', table);
    },
    isCurrentTable(table) {
      return this.currentTable && this.currentTable.name === table.name;
    },
  },
};
</script>
