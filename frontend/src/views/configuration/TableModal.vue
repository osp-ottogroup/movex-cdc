<template>
  <div class="modal" :class="{'is-active': isActive}">
    <div class="modal-background"
         @click="onClose"/>
    <div class="modal-card" style="width: auto">
      <header class="modal-card-head">
        <p class="modal-card-title">Add Table</p>
        <button class="delete"
                aria-label="close"
                @click="onClose">
        </button>
      </header>
      <section class="modal-card-body">
        <div class="select">
          <select v-model="selectedTable">
            <option v-for="table in tables" :key="table.id" :value="table">
              {{ table.name }}
            </option>
          </select>
        </div>
      </section>
      <footer class="modal-card-foot">
        <button class="button is-primary"
                @click="onAddButtonClicked">
          Add
        </button>
      </footer>
    </div>
  </div>
</template>

<script>
export default {
  name: 'TableModal',
  props: {
    tables: { type: Array, default: () => [] },
    isActive: { type: Boolean, default: false },
  },
  data() {
    return {
      selectedTable: null,
    };
  },
  methods: {
    onClose() {
      this.$emit('update:is-active', false);
    },
    onAddButtonClicked() {
      this.$emit('add-table', this.selectedTable);
    },
  },
};
</script>

<style lang="scss" scoped>
  footer button {
    margin-left: auto;
  }
</style>
